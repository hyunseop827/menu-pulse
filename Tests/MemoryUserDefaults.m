#import "MemoryUserDefaults.h"

@interface MPMemoryUserDefaults ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *storedValues;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *registeredValues;
@end

@implementation MPMemoryUserDefaults

- (instancetype)init {
    self = [super init];
    if (self) {
        _storedValues = [NSMutableDictionary dictionary];
        _registeredValues = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable id)objectForKey:(NSString *)defaultName {
    id value = self.storedValues[defaultName];
    return value ?: self.registeredValues[defaultName];
}

- (void)setObject:(nullable id)value forKey:(NSString *)defaultName {
    if (value) {
        self.storedValues[defaultName] = value;
    } else {
        [self.storedValues removeObjectForKey:defaultName];
    }
}

- (void)removeObjectForKey:(NSString *)defaultName {
    [self.storedValues removeObjectForKey:defaultName];
}

- (void)registerDefaults:(NSDictionary<NSString *, id> *)registrationDictionary {
    [self.registeredValues addEntriesFromDictionary:registrationDictionary];
}

- (BOOL)boolForKey:(NSString *)defaultName {
    return [[self objectForKey:defaultName] boolValue];
}

- (double)doubleForKey:(NSString *)defaultName {
    return [[self objectForKey:defaultName] doubleValue];
}

- (nullable NSString *)stringForKey:(NSString *)defaultName {
    id value = [self objectForKey:defaultName];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
    [self setObject:@(value) forKey:defaultName];
}

- (void)setDouble:(double)value forKey:(NSString *)defaultName {
    [self setObject:@(value) forKey:defaultName];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary<NSString *, id> *values = [self.registeredValues mutableCopy];
    [values addEntriesFromDictionary:self.storedValues];
    return values;
}

- (void)removePersistentDomainForName:(NSString *)domainName {
    (void)domainName;
    [self.storedValues removeAllObjects];
}

- (BOOL)synchronize {
    return YES;
}

@end
