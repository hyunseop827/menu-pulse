#import "TemperatureReader.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>
#import <Foundation/Foundation.h>
#import <math.h>

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

static const NSTimeInterval MPTemperatureFailureRetryInterval = 300.0;

BOOL MPTemperatureRetryAllowed(NSTimeInterval now, NSTimeInterval lastFailureTime) {
    return isnan(lastFailureTime) ||
        now - lastFailureTime >= MPTemperatureFailureRetryInterval;
}

static NSTimeInterval MPTemperatureMonotonicTime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

@interface MPHIDSensor : NSObject
@property(nonatomic, assign, readonly) IOHIDServiceClientRef service;
@property(nonatomic, copy, readonly) NSString *product;
- (instancetype)initWithService:(IOHIDServiceClientRef)service product:(NSString *)product;
@end

@implementation MPHIDSensor

- (instancetype)initWithService:(IOHIDServiceClientRef)service product:(NSString *)product {
    self = [super init];
    if (self) {
        _service = service ? (IOHIDServiceClientRef)CFRetain(service) : NULL;
        _product = [product copy];
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
- (nullable NSNumber *)temperatureCelsius;
@end

@interface MPHIDTemperatureReader ()
@property(nonatomic, assign) IOHIDEventSystemClientRef client;
@property(nonatomic, copy, nullable) NSArray<MPHIDSensor *> *sensors;
@property(nonatomic) NSTimeInterval lastFullFailureTime;
- (BOOL)initializeClient;
- (void)invalidateClient;
@end

@implementation MPHIDTemperatureReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastFullFailureTime = NAN;
        if (![self initializeClient]) {
            _lastFullFailureTime = MPTemperatureMonotonicTime();
        }
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
    if (activeSensors.count == 0) {
        [self invalidateClient];
        self.lastFullFailureTime = now;
        return nil;
    }

    NSNumber *hottestValue = nil;

    for (MPHIDSensor *sensor in activeSensors) {
        NSNumber *value = [self readTemperatureFromSensor:sensor];
        if (!value) {
            continue;
        }

        if (!hottestValue || value.doubleValue > hottestValue.doubleValue) {
            hottestValue = value;
        }
    }

    if (!hottestValue) {
        [self invalidateClient];
        self.lastFullFailureTime = now;
        return nil;
    }

    self.sensors = activeSensors;
    self.lastFullFailureTime = NAN;
    return hottestValue;
}

- (BOOL)initializeClient {
    if (self.client) {
        return YES;
    }

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
    self.sensors = nil;
    if (self.client) {
        CFRelease(self.client);
        self.client = NULL;
    }
}

- (NSArray<MPHIDSensor *> *)loadSensors {
    if (!self.client) {
        return @[];
    }

    CFArrayRef copiedServices = IOHIDEventSystemClientCopyServices(self.client);
    if (!copiedServices) {
        return @[];
    }

    NSArray *services = CFBridgingRelease(copiedServices);
    NSMutableArray<MPHIDSensor *> *sensors = [NSMutableArray arrayWithCapacity:services.count];

    for (id serviceObject in services) {
        IOHIDServiceClientRef service = (__bridge IOHIDServiceClientRef)serviceObject;
        NSString *product = [self productNameForService:service];
        if ([[product lowercaseString] containsString:@"battery"]) {
            continue;
        }

        [sensors addObject:[[MPHIDSensor alloc] initWithService:service product:product]];
    }

    return sensors;
}

- (NSNumber *)readTemperatureFromSensor:(MPHIDSensor *)sensor {
    IOHIDEventRef event = IOHIDServiceClientCopyEvent(sensor.service, 15, NULL, 0);
    if (!event) {
        return nil;
    }

    double value = IOHIDEventGetFloatValue(event, 15 << 16);
    CFRelease(event);

    if (value <= 0 || value >= 125) {
        return nil;
    }

    return @(value);
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

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} MPSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} MPSMCPowerLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} MPSMCKeyInfo;

typedef struct {
    uint8_t bytes[32];
} MPSMCBytes;

typedef struct {
    uint32_t key;
    MPSMCVersion vers;
    MPSMCPowerLimitData pLimitData;
    MPSMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    MPSMCBytes bytes;
} MPSMCParamStruct;

static const uint8_t MPSMCKeyNotFoundResult = 0x84;

static uint32_t MPSMCCode(NSString *value) {
    uint32_t result = 0;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    NSUInteger count = MIN((NSUInteger)4, data.length);

    for (NSUInteger index = 0; index < count; index += 1) {
        result = result << 8;
        result += bytes[index];
    }

    return result;
}

@interface MPSMCReader : NSObject
- (nullable instancetype)init;
- (nullable NSNumber *)temperatureCelsius;
@end

@interface MPSMCReader ()
@property(nonatomic) io_connect_t connection;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *keyInfoCache;
@property(nonatomic, strong) NSMutableSet<NSString *> *missingKeyCache;
@property(nonatomic) NSTimeInterval lastFullFailureTime;
@property(nonatomic, copy) NSArray<NSString *> *temperatureKeys;
@end

@implementation MPSMCReader

- (instancetype)init {
    io_service_t service = [MPSMCReader serviceNamed:@"AppleSMCKeysEndpoint"];
    if (service == IO_OBJECT_NULL) {
        service = [MPSMCReader serviceNamed:@"AppleSMC"];
    }

    if (service == IO_OBJECT_NULL) {
        return nil;
    }

    io_connect_t openedConnection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &openedConnection);
    IOObjectRelease(service);

    if (result != kIOReturnSuccess) {
        return nil;
    }

    self = [super init];
    if (self) {
        _connection = openedConnection;
        _keyInfoCache = [NSMutableDictionary dictionary];
        _missingKeyCache = [NSMutableSet set];
        _lastFullFailureTime = NAN;
        _temperatureKeys = @[
            @"TC0P", @"TC0E", @"TC0D", @"TCXC", @"TCXc",
            @"Tp09", @"Tp0T", @"Tp01", @"Tp05",
            @"TB0T", @"Ts0P",
        ];
    }
    return self;
}

- (void)dealloc {
    if (_connection != IO_OBJECT_NULL) {
        IOServiceClose(_connection);
    }
}

- (NSNumber *)temperatureCelsius {
    NSTimeInterval now = MPTemperatureMonotonicTime();
    if (!MPTemperatureRetryAllowed(now, self.lastFullFailureTime)) {
        return nil;
    }

    NSNumber *hottestValue = nil;

    for (NSString *key in self.temperatureKeys) {
        NSNumber *value = [self readTemperatureForKey:key];
        if (value && value.doubleValue > 0 && value.doubleValue < 125) {
            if (!hottestValue || value.doubleValue > hottestValue.doubleValue) {
                hottestValue = value;
            }
        }
    }

    if (hottestValue) {
        self.lastFullFailureTime = NAN;
        return hottestValue;
    }

    self.lastFullFailureTime = now;
    return nil;
}

+ (io_service_t)serviceNamed:(NSString *)name {
    return IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name.UTF8String));
}

- (NSNumber *)readTemperatureForKey:(NSString *)key {
    uint32_t type = 0;
    NSData *bytes = [self readKey:key type:&type];
    if (!bytes) {
        return nil;
    }

    const uint8_t *data = bytes.bytes;
    if (type == MPSMCCode(@"sp78") && bytes.length >= 2) {
        int8_t whole = (int8_t)data[0];
        return @((double)whole + (double)data[1] / 256.0);
    }

    if (type == MPSMCCode(@"fpe2") && bytes.length >= 2) {
        uint16_t raw = ((uint16_t)data[0] << 8) | (uint16_t)data[1];
        return @((double)raw / 4.0);
    }

    if (type == MPSMCCode(@"flt ") && bytes.length >= 4) {
        uint32_t raw = ((uint32_t)data[0] << 24) |
            ((uint32_t)data[1] << 16) |
            ((uint32_t)data[2] << 8) |
            (uint32_t)data[3];
        union {
            uint32_t bits;
            float value;
        } converted = { .bits = raw };
        return @((double)converted.value);
    }

    return nil;
}

- (NSData *)readKey:(NSString *)key type:(uint32_t *)type {
    if ([self.missingKeyCache containsObject:key]) {
        return nil;
    }

    MPSMCParamStruct input = {0};
    MPSMCParamStruct output = {0};
    MPSMCKeyInfo keyInfo = {0};

    NSValue *cachedInfo = self.keyInfoCache[key];
    if (cachedInfo) {
        [cachedInfo getValue:&keyInfo];
    } else {
        input.key = MPSMCCode(key);
        input.data8 = 9;

        kern_return_t result = [self callWithInput:&input output:&output];
        if (result != kIOReturnSuccess) {
            return nil;
        }

        if (output.result != 0) {
            if (output.result == MPSMCKeyNotFoundResult) {
                [self.missingKeyCache addObject:key];
            }
            return nil;
        }

        keyInfo = output.keyInfo;
        self.keyInfoCache[key] = [NSValue valueWithBytes:&keyInfo objCType:@encode(MPSMCKeyInfo)];
    }

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = MPSMCCode(key);
    input.keyInfo = keyInfo;
    input.data8 = 5;

    if ([self callWithInput:&input output:&output] != kIOReturnSuccess) {
        return nil;
    }
    if (output.result != 0) {
        if (output.result == MPSMCKeyNotFoundResult) {
            [self.missingKeyCache addObject:key];
        }
        return nil;
    }

    NSUInteger count = MIN((NSUInteger)keyInfo.dataSize, (NSUInteger)sizeof(output.bytes.bytes));
    if (type) {
        *type = keyInfo.dataType;
    }

    return [NSData dataWithBytes:output.bytes.bytes length:count];
}

- (kern_return_t)callWithInput:(MPSMCParamStruct *)input output:(MPSMCParamStruct *)output {
    size_t outputSize = sizeof(MPSMCParamStruct);
    return IOConnectCallStructMethod(
        self.connection,
        2,
        input,
        sizeof(MPSMCParamStruct),
        output,
        &outputSize
    );
}

@end

@interface MPTemperatureReader ()
@property(nonatomic, strong) MPHIDTemperatureReader *hidReader;
@property(nonatomic, strong, nullable) MPSMCReader *smcReader;
@property(nonatomic) NSTimeInterval lastSMCFailureTime;
@property(nonatomic) dispatch_queue_t queue;
@end

@implementation MPTemperatureReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _hidReader = [[MPHIDTemperatureReader alloc] init];
        _lastSMCFailureTime = NAN;
        _queue = dispatch_queue_create("MenuPulse.temperature-reader", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSNumber *)temperatureCelsius {
    NSNumber *hidTemperature = [self.hidReader temperatureCelsius];
    if (hidTemperature) {
        return hidTemperature;
    }

    MPSMCReader *reader = [self activeSMCReader];
    if (!reader) {
        return nil;
    }

    NSNumber *smcTemperature = [reader temperatureCelsius];
    if (!smcTemperature) {
        // A connected reader can become unusable after sleep or an IOKit
        // failure. Drop the connection so the next post-cooldown attempt
        // creates a fresh reader instead of retrying a dead one.
        self.smcReader = nil;
        self.lastSMCFailureTime = MPTemperatureMonotonicTime();
    }
    return smcTemperature;
}

- (void)temperatureCelsiusAsync:(MPTemperatureCompletion)completion {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        NSNumber *temperature = [weakSelf temperatureCelsius];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(temperature);
        });
    });
}

- (MPSMCReader *)activeSMCReader {
    if (self.smcReader) {
        return self.smcReader;
    }

    NSTimeInterval now = MPTemperatureMonotonicTime();
    if (!MPTemperatureRetryAllowed(now, self.lastSMCFailureTime)) {
        return nil;
    }

    self.smcReader = [[MPSMCReader alloc] init];
    if (!self.smcReader) {
        self.lastSMCFailureTime = now;
    }
    return self.smcReader;
}

@end
