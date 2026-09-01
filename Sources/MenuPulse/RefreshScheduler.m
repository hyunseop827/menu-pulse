#import "RefreshScheduler.h"

#import "SettingsStore.h"

#import <math.h>

const NSTimeInterval MPRefreshSchedulerNoPendingDelay = DBL_MAX;

@implementation MPSystemMonotonicClock

- (NSTimeInterval)monotonicTime {
    return NSProcessInfo.processInfo.systemUptime;
}

@end

@interface MPRefreshScheduler ()
@property(nonatomic, strong) id<MPMonotonicClock> clock;
@property(nonatomic, strong) dispatch_queue_t callbackQueue;
@property(nonatomic, copy) MPRefreshDueHandler dueHandler;
@property(nonatomic, strong) dispatch_source_t timer;
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, readwrite, getter=isTimerArmed) BOOL timerArmed;
@property(nonatomic) NSTimeInterval lastCPUTime;
@property(nonatomic) NSTimeInterval cpuWarmUpDeadline;
@property(nonatomic) NSTimeInterval lastRAMTime;
@property(nonatomic) NSTimeInterval lastTemperatureTime;
@property(nonatomic) NSTimeInterval lastDiskTime;
@property(nonatomic, readwrite) MPRefreshMetric pausedMetrics;
@property(nonatomic) NSTimeInterval cpuDeferredUntil;
@property(nonatomic) NSTimeInterval ramDeferredUntil;
@property(nonatomic) NSTimeInterval temperatureDeferredUntil;
@property(nonatomic) NSTimeInterval diskDeferredUntil;
@end

@implementation MPRefreshScheduler

- (instancetype)initWithDueHandler:(MPRefreshDueHandler)dueHandler {
    return [self initWithClock:[[MPSystemMonotonicClock alloc] init]
                callbackQueue:dispatch_get_main_queue()
                   dueHandler:dueHandler];
}

- (instancetype)initWithClock:(id<MPMonotonicClock>)clock
                 callbackQueue:(dispatch_queue_t)callbackQueue
                    dueHandler:(MPRefreshDueHandler)dueHandler {
    self = [super init];
    if (self) {
        _clock = clock;
        _callbackQueue = callbackQueue;
        _dueHandler = [dueHandler copy];
        _activeMetrics = MPRefreshMetricNone;
        _cpuRAMRefreshIntervalSeconds = MPCPURAMRefreshIntervalDefault;
        _temperatureRefreshIntervalSeconds = MPTemperatureRefreshIntervalDefault;
        _diskRefreshIntervalSeconds = MPDiskRefreshIntervalDefault;
        _lastCPUTime = NAN;
        _cpuWarmUpDeadline = NAN;
        _lastRAMTime = NAN;
        _lastTemperatureTime = NAN;
        _lastDiskTime = NAN;
        _cpuDeferredUntil = NAN;
        _ramDeferredUntil = NAN;
        _temperatureDeferredUntil = NAN;
        _diskDeferredUntil = NAN;

        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, callbackQueue);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_timer, ^{
            [weakSelf processDueMetrics];
        });
        dispatch_source_set_timer(_timer,
                                  DISPATCH_TIME_FOREVER,
                                  DISPATCH_TIME_FOREVER,
                                  0);
        dispatch_activate(_timer);
    }
    return self;
}

- (void)dealloc {
    dispatch_source_cancel(_timer);
}

- (void)setActiveMetrics:(MPRefreshMetric)activeMetrics {
    MPRefreshMetric validatedMetrics = activeMetrics & MPRefreshMetricAll;
    if (_activeMetrics == validatedMetrics) {
        return;
    }

    MPRefreshMetric changedMetrics = _activeMetrics ^ validatedMetrics;
    MPRefreshMetric disabledMetrics = _activeMetrics & ~validatedMetrics;
    _activeMetrics = validatedMetrics;
    _pausedMetrics &= ~disabledMetrics;
    [self invalidateTimesForMetrics:changedMetrics];

    if (!self.running) {
        return;
    }

    if (_activeMetrics == MPRefreshMetricNone) {
        [self disarmTimer];
        return;
    }
    [self processDueMetrics];
}

- (void)setCpuRAMRefreshIntervalSeconds:(NSTimeInterval)cpuRAMRefreshIntervalSeconds {
    NSTimeInterval validatedInterval =
        [MPSettingsStore isValidCPURAMRefreshInterval:cpuRAMRefreshIntervalSeconds]
        ? cpuRAMRefreshIntervalSeconds
        : MPCPURAMRefreshIntervalDefault;
    if (_cpuRAMRefreshIntervalSeconds == validatedInterval) {
        return;
    }

    _cpuRAMRefreshIntervalSeconds = validatedInterval;
    if (self.running) {
        [self processDueMetrics];
    }
}

- (void)setTemperatureRefreshIntervalSeconds:(NSTimeInterval)temperatureRefreshIntervalSeconds {
    NSTimeInterval validatedInterval =
        [MPSettingsStore isValidTemperatureRefreshInterval:
            temperatureRefreshIntervalSeconds]
        ? temperatureRefreshIntervalSeconds
        : MPTemperatureRefreshIntervalDefault;
    if (_temperatureRefreshIntervalSeconds == validatedInterval) {
        return;
    }

    _temperatureRefreshIntervalSeconds = validatedInterval;
    if (self.running) {
        [self processDueMetrics];
    }
}

- (void)setDiskRefreshIntervalSeconds:(NSTimeInterval)diskRefreshIntervalSeconds {
    NSTimeInterval validatedInterval =
        [MPSettingsStore isValidDiskRefreshInterval:diskRefreshIntervalSeconds]
        ? diskRefreshIntervalSeconds
        : MPDiskRefreshIntervalDefault;
    if (_diskRefreshIntervalSeconds == validatedInterval) {
        return;
    }

    _diskRefreshIntervalSeconds = validatedInterval;
    if (self.running) {
        [self processDueMetrics];
    }
}

- (void)start {
    if (self.running) {
        return;
    }

    self.running = YES;
    [self processDueMetrics];
}

- (void)stop {
    if (!self.running) {
        return;
    }

    self.running = NO;
    [self disarmTimer];
}

- (MPRefreshMetric)processDueMetrics {
    NSTimeInterval now = self.clock.monotonicTime;
    MPRefreshMetric dueMetrics = [self dueMetricsAtTime:now];
    if (dueMetrics != MPRefreshMetricNone) {
        [self markMetrics:dueMetrics sampledAtTime:now];
        self.dueHandler(dueMetrics);
    }

    if (self.running) {
        [self scheduleNextTimerAtTime:self.clock.monotonicTime];
    }
    return dueMetrics;
}

- (void)markMetricsSampled:(MPRefreshMetric)metrics {
    [self markMetrics:(metrics & MPRefreshMetricAll) sampledAtTime:self.clock.monotonicTime];
    if (self.running) {
        [self scheduleNextTimerAtTime:self.clock.monotonicTime];
    }
}

- (void)prepareCPUWarmUp {
    if ((self.activeMetrics & MPRefreshMetricCPU) == 0) {
        return;
    }

    NSTimeInterval now = self.clock.monotonicTime;
    self.lastCPUTime = now;
    self.cpuWarmUpDeadline = now + 1.0;
    if (self.running) {
        [self scheduleNextTimerAtTime:now];
    }
}

- (void)invalidateLastSampleForMetrics:(MPRefreshMetric)metrics {
    [self invalidateTimesForMetrics:(metrics & MPRefreshMetricAll)];
    if (self.running) {
        [self processDueMetrics];
    }
}

- (void)setMetric:(MPRefreshMetric)metric paused:(BOOL)paused {
    MPRefreshMetric metrics = metric & MPRefreshMetricAll;
    if (paused) {
        metrics &= self.activeMetrics;
    }
    if (metrics == MPRefreshMetricNone) {
        return;
    }

    MPRefreshMetric updatedPausedMetrics = paused
        ? self.pausedMetrics | metrics
        : self.pausedMetrics & ~metrics;
    if (self.pausedMetrics == updatedPausedMetrics) {
        return;
    }

    MPRefreshMetric resumedMetrics = self.pausedMetrics & ~updatedPausedMetrics;
    self.pausedMetrics = updatedPausedMetrics;
    if (resumedMetrics != MPRefreshMetricNone) {
        [self markMetrics:(resumedMetrics & self.activeMetrics)
            sampledAtTime:self.clock.monotonicTime];
    }

    if (self.running) {
        [self scheduleNextTimerAtTime:self.clock.monotonicTime];
    }
}

- (void)deferMetric:(MPRefreshMetric)metric forInterval:(NSTimeInterval)interval {
    MPRefreshMetric metrics = metric & MPRefreshMetricAll;
    if (metrics == MPRefreshMetricNone || !isfinite(interval) || interval < 0.0) {
        return;
    }

    NSTimeInterval deferredUntil = self.clock.monotonicTime + interval;
    MPRefreshMetric individualMetrics[] = {
        MPRefreshMetricCPU,
        MPRefreshMetricRAM,
        MPRefreshMetricTemperature,
        MPRefreshMetricDisk,
    };
    for (NSUInteger index = 0;
         index < sizeof(individualMetrics) / sizeof(individualMetrics[0]);
         index += 1) {
        MPRefreshMetric individualMetric = individualMetrics[index];
        if ((metrics & individualMetric) == 0) {
            continue;
        }

        NSTimeInterval existingDeadline = [self deferredUntilForMetric:individualMetric];
        NSTimeInterval updatedDeadline = isnan(existingDeadline)
            ? deferredUntil
            : MAX(existingDeadline, deferredUntil);
        [self setDeferredUntil:updatedDeadline forMetric:individualMetric];
    }

    if (self.running) {
        [self scheduleNextTimerAtTime:self.clock.monotonicTime];
    }
}

- (MPRefreshMetric)dueMetricsAtCurrentTime {
    return [self dueMetricsAtTime:self.clock.monotonicTime];
}

- (NSTimeInterval)nextDelayAtCurrentTime {
    return [self nextDelayAtTime:self.clock.monotonicTime];
}

- (NSTimeInterval)lastSampleTimeForMetric:(MPRefreshMetric)metric {
    switch (metric) {
        case MPRefreshMetricCPU:
            return self.lastCPUTime;
        case MPRefreshMetricRAM:
            return self.lastRAMTime;
        case MPRefreshMetricTemperature:
            return self.lastTemperatureTime;
        case MPRefreshMetricDisk:
            return self.lastDiskTime;
        default:
            return NAN;
    }
}

+ (NSTimeInterval)leewayForDelay:(NSTimeInterval)delay {
    return MIN(MAX(delay * 0.1, 0.1), 5.0);
}

- (MPRefreshMetric)dueMetricsAtTime:(NSTimeInterval)now {
    MPRefreshMetric dueMetrics = MPRefreshMetricNone;
    if ([self metric:MPRefreshMetricCPU isDueAtTime:now]) {
        dueMetrics |= MPRefreshMetricCPU;
    }
    if ([self metric:MPRefreshMetricRAM isDueAtTime:now]) {
        dueMetrics |= MPRefreshMetricRAM;
    }
    if ([self metric:MPRefreshMetricTemperature isDueAtTime:now]) {
        dueMetrics |= MPRefreshMetricTemperature;
    }
    if ([self metric:MPRefreshMetricDisk isDueAtTime:now]) {
        dueMetrics |= MPRefreshMetricDisk;
    }

    // CPU and RAM use the same sampling interval. If one is enabled later, its
    // first sample would otherwise leave the two metrics on separate deadlines
    // and double the number of timer wake-ups. Sample both whenever either is
    // due so their cadence stays aligned.
    MPRefreshMetric cpuRAMMetrics = MPRefreshMetricCPU | MPRefreshMetricRAM;
    BOOL bothCPURAMMetricsCanRun =
        [self metricCanRun:MPRefreshMetricCPU atTime:now] &&
        [self metricCanRun:MPRefreshMetricRAM atTime:now];
    BOOL cpuWarmUpIsPending =
        !isnan(self.cpuWarmUpDeadline) &&
        (dueMetrics & MPRefreshMetricCPU) == MPRefreshMetricNone;
    if (bothCPURAMMetricsCanRun &&
        !cpuWarmUpIsPending &&
        (dueMetrics & cpuRAMMetrics) != MPRefreshMetricNone) {
        dueMetrics |= cpuRAMMetrics;
    }
    return dueMetrics;
}

- (BOOL)metric:(MPRefreshMetric)metric isDueAtTime:(NSTimeInterval)now {
    if (![self metricCanRun:metric atTime:now]) {
        return NO;
    }

    if (metric == MPRefreshMetricCPU && !isnan(self.cpuWarmUpDeadline)) {
        return now >= self.cpuWarmUpDeadline;
    }

    NSTimeInterval lastSampleTime = [self lastSampleTimeForMetric:metric];
    if (isnan(lastSampleTime)) {
        return YES;
    }

    return now - lastSampleTime >= [self intervalForMetric:metric];
}

- (BOOL)metricCanRun:(MPRefreshMetric)metric atTime:(NSTimeInterval)now {
    if ((self.activeMetrics & metric) == 0 ||
        (self.pausedMetrics & metric) != 0) {
        return NO;
    }

    NSTimeInterval deferredUntil = [self deferredUntilForMetric:metric];
    return isnan(deferredUntil) || now >= deferredUntil;
}

- (NSTimeInterval)nextDelayAtTime:(NSTimeInterval)now {
    MPRefreshMetric schedulableMetrics = self.activeMetrics & ~self.pausedMetrics;
    if (schedulableMetrics == MPRefreshMetricNone) {
        return MPRefreshSchedulerNoPendingDelay;
    }

    NSTimeInterval delay = MPRefreshSchedulerNoPendingDelay;
    MPRefreshMetric metrics[] = {
        MPRefreshMetricCPU,
        MPRefreshMetricRAM,
        MPRefreshMetricTemperature,
        MPRefreshMetricDisk,
    };
    for (NSUInteger index = 0; index < sizeof(metrics) / sizeof(metrics[0]); index += 1) {
        MPRefreshMetric metric = metrics[index];
        if ((schedulableMetrics & metric) == 0) {
            continue;
        }

        NSTimeInterval metricDeadline;
        if (metric == MPRefreshMetricCPU && !isnan(self.cpuWarmUpDeadline)) {
            metricDeadline = self.cpuWarmUpDeadline;
        } else {
            NSTimeInterval lastSampleTime = [self lastSampleTimeForMetric:metric];
            metricDeadline = isnan(lastSampleTime)
                ? now
                : lastSampleTime + [self intervalForMetric:metric];
        }

        NSTimeInterval deferredUntil = [self deferredUntilForMetric:metric];
        if (!isnan(deferredUntil)) {
            metricDeadline = MAX(metricDeadline, deferredUntil);
        }
        delay = MIN(delay, MAX(metricDeadline - now, 0.0));
    }
    return delay;
}

- (NSTimeInterval)intervalForMetric:(MPRefreshMetric)metric {
    switch (metric) {
        case MPRefreshMetricCPU:
        case MPRefreshMetricRAM:
            return self.cpuRAMRefreshIntervalSeconds;
        case MPRefreshMetricTemperature:
            return self.temperatureRefreshIntervalSeconds;
        case MPRefreshMetricDisk:
            return self.diskRefreshIntervalSeconds;
        default:
            return MPRefreshSchedulerNoPendingDelay;
    }
}

- (NSTimeInterval)deferredUntilForMetric:(MPRefreshMetric)metric {
    switch (metric) {
        case MPRefreshMetricCPU:
            return self.cpuDeferredUntil;
        case MPRefreshMetricRAM:
            return self.ramDeferredUntil;
        case MPRefreshMetricTemperature:
            return self.temperatureDeferredUntil;
        case MPRefreshMetricDisk:
            return self.diskDeferredUntil;
        default:
            return NAN;
    }
}

- (void)setDeferredUntil:(NSTimeInterval)deferredUntil
                forMetric:(MPRefreshMetric)metric {
    switch (metric) {
        case MPRefreshMetricCPU:
            self.cpuDeferredUntil = deferredUntil;
            break;
        case MPRefreshMetricRAM:
            self.ramDeferredUntil = deferredUntil;
            break;
        case MPRefreshMetricTemperature:
            self.temperatureDeferredUntil = deferredUntil;
            break;
        case MPRefreshMetricDisk:
            self.diskDeferredUntil = deferredUntil;
            break;
        default:
            break;
    }
}

- (void)markMetrics:(MPRefreshMetric)metrics sampledAtTime:(NSTimeInterval)time {
    if ((metrics & MPRefreshMetricCPU) != 0) {
        self.lastCPUTime = time;
        self.cpuWarmUpDeadline = NAN;
    }
    if ((metrics & MPRefreshMetricRAM) != 0) {
        self.lastRAMTime = time;
    }
    if ((metrics & MPRefreshMetricTemperature) != 0) {
        self.lastTemperatureTime = time;
    }
    if ((metrics & MPRefreshMetricDisk) != 0) {
        self.lastDiskTime = time;
    }
}

- (void)invalidateTimesForMetrics:(MPRefreshMetric)metrics {
    if ((metrics & MPRefreshMetricCPU) != 0) {
        self.lastCPUTime = NAN;
        self.cpuWarmUpDeadline = NAN;
    }
    if ((metrics & MPRefreshMetricRAM) != 0) {
        self.lastRAMTime = NAN;
    }
    if ((metrics & MPRefreshMetricTemperature) != 0) {
        self.lastTemperatureTime = NAN;
    }
    if ((metrics & MPRefreshMetricDisk) != 0) {
        self.lastDiskTime = NAN;
    }
}

- (void)scheduleNextTimerAtTime:(NSTimeInterval)now {
    NSTimeInterval delay = [self nextDelayAtTime:now];
    if (delay == MPRefreshSchedulerNoPendingDelay) {
        [self disarmTimer];
        return;
    }

    NSTimeInterval leeway = [self.class leewayForDelay:delay];
    uint64_t delayNanoseconds = (uint64_t)llround(delay * (NSTimeInterval)NSEC_PER_SEC);
    uint64_t leewayNanoseconds = (uint64_t)llround(leeway * (NSTimeInterval)NSEC_PER_SEC);
    dispatch_source_set_timer(self.timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)delayNanoseconds),
                              DISPATCH_TIME_FOREVER,
                              leewayNanoseconds);
    self.timerArmed = YES;
}

- (void)disarmTimer {
    dispatch_source_set_timer(self.timer,
                              DISPATCH_TIME_FOREVER,
                              DISPATCH_TIME_FOREVER,
                              0);
    self.timerArmed = NO;
}

@end
