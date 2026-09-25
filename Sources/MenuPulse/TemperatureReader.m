#import "TemperatureReader.h"

#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>

typedef CFTypeRef IOHIDEventRef;

extern IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(
    IOHIDServiceClientRef service,
    int64_t type,
    CFDictionaryRef _Nullable matching,
    uint32_t options
);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

const NSTimeInterval MPTemperatureFailureRetryInterval = 300.0;

BOOL MPTemperatureRetryAllowed(NSTimeInterval now, NSTimeInterval lastFailureTime) {
    return isnan(lastFailureTime) || now - lastFailureTime >= MPTemperatureFailureRetryInterval;
}

BOOL MPTemperatureSensorIsExcluded(NSString *product) {
    // Battery gauges are not component temperatures. PMU "tcal" calibration
    // channels report a constant value (51.85 °C on M1) that would otherwise
    // hide every cooler reading behind a fixed floor.
    for (NSString *excluded in @[@"battery", @"tcal"]) {
        if ([product rangeOfString:excluded options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSTimeInterval MPTemperatureMonotonicTime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

@interface MPHIDSensor : NSObject
@property(nonatomic, assign, readonly) IOHIDServiceClientRef service;
- (instancetype)initWithService:(IOHIDServiceClientRef)service;
@end

@implementation MPHIDSensor

- (instancetype)initWithService:(IOHIDServiceClientRef)service {
    self = [super init];
    if (self) {
        _service = service ? (IOHIDServiceClientRef)CFRetain(service) : NULL;
    }
    return self;
}

- (void)dealloc {
    if (_service) {
        CFRelease(_service);
    }
}

@end

@interface MPHIDTemperatureReader : NSObject
@property(nonatomic, assign) IOHIDEventSystemClientRef client;
@property(nonatomic, copy, nullable) NSArray<MPHIDSensor *> *sensors;
@property(nonatomic) NSTimeInterval lastFullFailureTime;
- (nullable NSNumber *)temperatureCelsius;
- (void)invalidateClient;
@end

@implementation MPHIDTemperatureReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastFullFailureTime = NAN;
    }
    return self;
}

- (void)dealloc {
    if (_client) {
        CFRelease(_client);
    }
}

- (NSNumber *)temperatureCelsius {
    NSTimeInterval now = MPTemperatureMonotonicTime();
    if (!self.sensors && !MPTemperatureRetryAllowed(now, self.lastFullFailureTime)) {
        return nil;
    }

    if (!self.client && ![self initializeClient]) {
        self.lastFullFailureTime = now;
        return nil;
    }

    NSArray<MPHIDSensor *> *activeSensors = self.sensors ?: [self loadSensors];
    NSMutableArray<MPHIDSensor *> *liveSensors =
        [NSMutableArray arrayWithCapacity:activeSensors.count];
    NSNumber *hottestValue = nil;

    for (MPHIDSensor *sensor in activeSensors) {
        double value = 0.0;
        if (![self readSensor:sensor value:&value]) {
            // A missing event can be transient, so the sensor stays listed.
            [liveSensors addObject:sensor];
            continue;
        }
        if (value <= 0 || value >= 125) {
            // Disconnected channels report impossible values on every read.
            continue;
        }

        [liveSensors addObject:sensor];
        if (!hottestValue || value > hottestValue.doubleValue) {
            hottestValue = @(value);
        }
    }

    if (!hottestValue) {
        [self invalidateClient];
        self.lastFullFailureTime = now;
        return nil;
    }

    // Later reads skip sensors that reported impossible values. Invalidating
    // the client, as display sleep does, enumerates every sensor again.
    self.sensors = liveSensors;
    self.lastFullFailureTime = NAN;
    return hottestValue;
}

- (BOOL)initializeClient {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        return NO;
    }

    NSDictionary *matching = @{
        @"PrimaryUsagePage": @0xff00,
        @"PrimaryUsage": @5,
    };
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);
    self.client = client;
    return YES;
}

- (void)invalidateClient {
    // Keep lastFullFailureTime so disabling and re-enabling the metric cannot
    // bypass the retry cooldown after a hardware failure.
    self.sensors = nil;
    if (self.client) {
        CFRelease(self.client);
        self.client = NULL;
    }
}

- (NSArray<MPHIDSensor *> *)loadSensors {
    CFArrayRef copiedServices = IOHIDEventSystemClientCopyServices(self.client);
    if (!copiedServices) {
        return @[];
    }

    NSArray *services = CFBridgingRelease(copiedServices);
    NSMutableArray<MPHIDSensor *> *sensors = [NSMutableArray arrayWithCapacity:services.count];

    for (id serviceObject in services) {
        IOHIDServiceClientRef service = (__bridge IOHIDServiceClientRef)serviceObject;
        if (MPTemperatureSensorIsExcluded([self productNameForService:service])) {
            continue;
        }

        [sensors addObject:[[MPHIDSensor alloc] initWithService:service]];
    }

    return sensors;
}

- (BOOL)readSensor:(MPHIDSensor *)sensor value:(double *)value {
    IOHIDEventRef event = IOHIDServiceClientCopyEvent(sensor.service, 15, NULL, 0);
    if (!event) {
        return NO;
    }

    *value = IOHIDEventGetFloatValue(event, 15 << 16);
    CFRelease(event);
    return YES;
}

- (NSString *)productNameForService:(IOHIDServiceClientRef)service {
    CFTypeRef copiedValue = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
    if (!copiedValue) {
        return @"";
    }

    id value = CFBridgingRelease(copiedValue);
    return [value description] ?: @"";
}

@end

@interface MPTemperatureReader ()
@property(nonatomic, strong) MPHIDTemperatureReader *hidReader;
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic, strong) NSLock *cancellationLock;
@property(nonatomic) NSUInteger cancellationGeneration;
@end

@implementation MPTemperatureReader

static const void *MPTemperatureReaderQueueKey = &MPTemperatureReaderQueueKey;

- (instancetype)init {
    self = [super init];
    if (self) {
        _hidReader = [[MPHIDTemperatureReader alloc] init];
        // Periodic sensor polling has no waiting user, so it runs at utility
        // QoS instead of inheriting the main thread's interactive priority.
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL,
            QOS_CLASS_UTILITY,
            0
        );
        _queue = dispatch_queue_create("MenuPulse.temperature-reader", attributes);
        _cancellationLock = [[NSLock alloc] init];
        dispatch_queue_set_specific(
            _queue,
            MPTemperatureReaderQueueKey,
            (__bridge void *)self,
            NULL
        );
    }
    return self;
}

- (NSNumber *)readTemperatureCelsius {
    return [self.hidReader temperatureCelsius];
}

- (void)temperatureCelsiusAsync:(MPTemperatureCompletion)completion {
    __weak typeof(self) weakSelf = self;
    MPTemperatureCompletion copiedCompletion = [completion copy];

    [self.cancellationLock lock];
    NSUInteger generation = self.cancellationGeneration;
    dispatch_async(self.queue, ^{
        MPTemperatureReader *strongSelf = weakSelf;
        if (![strongSelf isCancellationGenerationCurrent:generation]) {
            // The request never started sensor I/O. Its owner already cleared
            // the in-flight state while disabling temperature, so no stale
            // nil completion is needed.
            return;
        }

        NSNumber *temperature = [strongSelf readTemperatureCelsius];
        dispatch_async(dispatch_get_main_queue(), ^{
            copiedCompletion(temperature);
        });
    });
    [self.cancellationLock unlock];
}

- (void)invalidateHardware {
    void (^invalidateBlock)(void) = ^{
        [self.hidReader invalidateClient];
    };

    // Advance the generation and enqueue invalidation under the same lock used
    // when reads capture their token. This keeps queue order deterministic even
    // if callers arrive from different threads.
    [self.cancellationLock lock];
    self.cancellationGeneration += 1;
    if ([self isOnReaderQueue]) {
        [self.cancellationLock unlock];
        invalidateBlock();
    } else {
        // Enqueue behind any active read without blocking the settings UI.
        // A subsequent read is queued after this block, preserving
        // read -> invalidate -> read ordering across a quick off/on toggle.
        dispatch_async(self.queue, invalidateBlock);
        [self.cancellationLock unlock];
    }
}

- (BOOL)isOnReaderQueue {
    return dispatch_get_specific(MPTemperatureReaderQueueKey) == (__bridge void *)self;
}

- (BOOL)isCancellationGenerationCurrent:(NSUInteger)generation {
    [self.cancellationLock lock];
    BOOL isCurrent = generation == self.cancellationGeneration;
    [self.cancellationLock unlock];
    return isCurrent;
}

@end
