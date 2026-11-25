import CoreGraphics
import Foundation

/// Tunable constants for the rope solver.
///
/// The defaults are the "thread" rope at three in the afternoon. A ``RopeStyle`` and a
/// ``RopeTimeProfile`` are applied on top by ``applying(_:at:)``; nothing else should
/// write the physics values, so the configuration and the style can never disagree.
public struct RopeConfiguration: Equatable, Sendable {
    public var segmentCount: Int
    /// Rest length of one link, in points.
    public var segmentLength: Double
    /// Points per second squared. Screen coordinates are y-down.
    public var gravity: Double
    /// Fraction of last step's displacement kept. 1 is lossless.
    public var damping: Double
    public var constraintIterations: Int
    public var stretchPasses: Int
    public var convergenceTolerance: Double
    /// Hard ceiling on any link's length, as a multiple of its rest length.
    public var maxStretchRatio: Double
    public var fixedTimeStep: Double
    /// Longest wall-clock frame the solver will catch up on.
    public var maxFrameDuration: Double
    /// Points per second. Bounds integration and the held node.
    public var maximumSpeed: Double
    public var maximumReachRatio: Double
    /// Below this speed (points per second) every node counts as still.
    public var restSpeed: Double
    public var framesBeforeSleep: Int
    /// Angle from vertical the rope starts at, so a fresh charm swings into view.
    public var initialAngle: Double
    /// Fraction of each link's error corrected per pass. Below 1 the cord has give.
    public var linkStiffness: Double = 1
    /// The length charms are sized against, in points. Independent of rope length.
    public var charmUnit: Double = 260

    public var pointCount: Int { segmentCount + 1 }
    public var totalLength: Double { Double(segmentCount) * segmentLength }

    public init(
        segmentCount: Int, segmentLength: Double, gravity: Double, damping: Double,
        constraintIterations: Int, stretchPasses: Int, convergenceTolerance: Double,
        maxStretchRatio: Double, fixedTimeStep: Double, maxFrameDuration: Double,
        maximumSpeed: Double, maximumReachRatio: Double, restSpeed: Double,
        framesBeforeSleep: Int, initialAngle: Double
    ) {
        self.segmentCount = segmentCount
        self.segmentLength = segmentLength
        self.gravity = gravity
        self.damping = damping
        self.constraintIterations = constraintIterations
        self.stretchPasses = stretchPasses
        self.convergenceTolerance = convergenceTolerance
        self.maxStretchRatio = maxStretchRatio
        self.fixedTimeStep = fixedTimeStep
        self.maxFrameDuration = maxFrameDuration
        self.maximumSpeed = maximumSpeed
        self.maximumReachRatio = maximumReachRatio
        self.restSpeed = restSpeed
        self.framesBeforeSleep = framesBeforeSleep
        self.initialAngle = initialAngle
    }

    public static let `default` = RopeConfiguration(
        segmentCount: 20,
        segmentLength: 13,
        gravity: 2000,
        damping: 0.999,
        constraintIterations: 256,
        stretchPasses: 256,
        convergenceTolerance: 0.05,
        maxStretchRatio: 1.02,
        fixedTimeStep: 1.0 / 240.0,
        maxFrameDuration: 0.1,
        maximumSpeed: 6000,
        maximumReachRatio: 0.98,
        restSpeed: 4.0,
        framesBeforeSleep: 60,
        initialAngle: 0.38
    )

    /// The elastic cord's ceiling: it may stretch to half again its length.
    public static let elasticCeiling = 1.5

    /// Builds a configuration for a rope whose shipped length is `unit` points.
    /// - Parameters:
    ///   - unit: Base rope length in points before `ropeLength` scales it.
    ///   - ropeLength: Multiplier on the rope's length (0.5...1.8).
    public static func make(
        unit: Double,
        ropeLength: Double = 1,
        style: RopeStyle = .default,
        profile: RopeTimeProfile = .baseline,
        elastic: Bool = false,
        swingWeight: Double = 1,
        settleSpeed: Double = 1
    ) -> RopeConfiguration {
        var configuration = RopeConfiguration.default
        configuration.charmUnit = max(40, unit)
        configuration.segmentLength = configuration.charmUnit * max(0.2, ropeLength) / Double(configuration.segmentCount)
        configuration = configuration.applying(style, at: profile)
        // The user's own feel goes on last, scaling whatever the style and time decided.
        configuration.gravity *= min(max(swingWeight, 0.2), 3)
        configuration.damping = 1 - ((1 - configuration.damping) * min(max(settleSpeed, 0.1), 5))
        if elastic {
            configuration.maxStretchRatio = elasticCeiling
            configuration.linkStiffness = 0.18
            configuration.constraintIterations = 6
            configuration.convergenceTolerance = 0
        }
        return configuration
    }

    /// Applies a style and then a time profile, always starting from the defaults so
    /// applying morning then afternoon gives the afternoon.
    public func applying(_ style: RopeStyle, at profile: RopeTimeProfile = .baseline) -> RopeConfiguration {
        let physics = style.physics
        let defaults = RopeConfiguration.default
        var configuration = self
        configuration.gravity = defaults.gravity * physics.gravityScale
        configuration.damping = physics.damping
        configuration.maxStretchRatio = physics.maxStretchRatio
        configuration.constraintIterations = physics.constraintIterations
        configuration.stretchPasses = physics.stretchPasses
        configuration.linkStiffness = 1
        configuration.convergenceTolerance = defaults.convergenceTolerance

        let time = profile.physics
        configuration.damping = 1 - ((1 - configuration.damping) * time.energyLossScale)
        configuration.initialAngle = defaults.initialAngle * time.releaseAngleScale
        configuration.restSpeed = defaults.restSpeed * time.restSpeedScale
        return configuration
    }

    /// Extra room a grab gets beyond the charm's own outline.
    public static let grabPadding = 8.0
}
