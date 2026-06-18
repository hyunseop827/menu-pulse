#import "TemperatureReader.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>
#import <Foundation/Foundation.h>

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
@property(nonatomic, strong, nullable) MPHIDSensor *lastWorkingSensor;
@property(nonatomic, strong) NSDate *lastFullFailure;
@end

@implementation MPHIDTemperatureReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastFullFailure = [NSDate distantPast];
        _client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (_client) {
            NSDictionary *matching = @{
                @"PrimaryUsagePage": @0xff00,
                @"PrimaryUsage": @5,
            };
            IOHIDEventSystemClientSetMatching(_client, (__bridge CFDictionaryRef)matching);
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
    if (self.lastWorkingSensor) {
        NSNumber *value = [self readTemperatureFromSensor:self.lastWorkingSensor];
        if (value) {
            return value;
        }
    }

    NSDate *now = [NSDate date];
    if (!self.sensors && [now timeIntervalSinceDate:self.lastFullFailure] < MPTemperatureFailureRetryInterval) {
        return nil;
    }

    NSArray<MPHIDSensor *> *activeSensors = self.sensors ?: [self loadSensors];
    if (activeSensors.count == 0) {
        self.sensors = nil;
        self.lastWorkingSensor = nil;
        self.lastFullFailure = now;
        return nil;
    }

    NSMutableArray<MPHIDSensor *> *workingSensors = [NSMutableArray array];
    MPHIDSensor *hottestSensor = nil;
    NSNumber *hottestValue = nil;

    for (MPHIDSensor *sensor in activeSensors) {
        NSNumber *value = [self readTemperatureFromSensor:sensor];
        if (!value) {
            continue;
        }

        [workingSensors addObject:sensor];
        if (!hottestValue || value.doubleValue > hottestValue.doubleValue) {
            hottestSensor = sensor;
            hottestValue = value;
        }
    }

    if (!hottestValue) {
        self.sensors = nil;
        self.lastWorkingSensor = nil;
        self.lastFullFailure = now;
        return nil;
    }

    self.sensors = workingSensors;
    self.lastWorkingSensor = hottestSensor;
    return hottestValue;
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
@property(nonatomic, copy, nullable) NSString *cachedTemperatureKey;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *keyInfoCache;
@property(nonatomic, strong) NSDate *lastFullFailure;
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
        _lastFullFailure = [NSDate distantPast];
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
    NSDate *now = [NSDate date];
    if (!self.cachedTemperatureKey &&
        [now timeIntervalSinceDate:self.lastFullFailure] < MPTemperatureFailureRetryInterval) {
        return nil;
    }

    if (self.cachedTemperatureKey) {
        NSNumber *value = [self readTemperatureForKey:self.cachedTemperatureKey];
        if (value && value.doubleValue > 0 && value.doubleValue < 125) {
            return value;
        }
    }

    for (NSString *key in self.temperatureKeys) {
        NSNumber *value = [self readTemperatureForKey:key];
        if (value && value.doubleValue > 0 && value.doubleValue < 125) {
            self.cachedTemperatureKey = key;
            return value;
        }
    }

    self.cachedTemperatureKey = nil;
    self.lastFullFailure = now;
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
    MPSMCParamStruct input = {0};
    MPSMCParamStruct output = {0};
    MPSMCKeyInfo keyInfo = {0};

    NSValue *cachedInfo = self.keyInfoCache[key];
    if (cachedInfo) {
        [cachedInfo getValue:&keyInfo];
    } else {
        input.key = MPSMCCode(key);
        input.data8 = 9;

        if ([self callWithInput:&input output:&output] != kIOReturnSuccess || output.result != 0) {
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

    if ([self callWithInput:&input output:&output] != kIOReturnSuccess || output.result != 0) {
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
@property(nonatomic) BOOL didInitializeSMCReader;
@property(nonatomic) dispatch_queue_t queue;
@end

@implementation MPTemperatureReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _hidReader = [[MPHIDTemperatureReader alloc] init];
        _queue = dispatch_queue_create("MenuPulse.temperature-reader", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSNumber *)temperatureCelsius {
    NSNumber *hidTemperature = [self.hidReader temperatureCelsius];
    if (hidTemperature) {
        return hidTemperature;
    }

    return [[self activeSMCReader] temperatureCelsius];
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
    if (!self.didInitializeSMCReader) {
        self.smcReader = [[MPSMCReader alloc] init];
        self.didInitializeSMCReader = YES;
    }

    return self.smcReader;
}

@end
