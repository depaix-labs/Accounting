import Accounting
import Foundation

public enum ProjectionPipeline {
    /// Render validated resolved-posting output using the established
    /// native projection pipeline while keeping its source provenance
    /// available to the caller.
    public static func render(
        _ output: NativeResolvedCompileOutput,
        as kind: ProjectionKind,
        options: NativeRenderOptions = .init(),
        showProjectionDiagnostics: Bool = false
    ) throws {
        try render(
            output.output,
            as: kind,
            options: options,
            showProjectionDiagnostics: showProjectionDiagnostics
        )
    }

    public static func render(
        _ output: NativeCompileOutput,
        as kind: ProjectionKind,
        options: NativeRenderOptions = .init(),
        showProjectionDiagnostics: Bool = false
    ) throws {
        let projected = try ProjectionRunner.project(output, as: kind)
        try ProjectionRenderDispatcher.render(
            projected,
            options: options,
            showProjectionDiagnostics: showProjectionDiagnostics
        )
    }

    public static func render(
        _ output: NativePeriodCompileOutput,
        as kind: ProjectionKind,
        options: NativeRenderOptions = .init(),
        showProjectionDiagnostics: Bool = false
    ) throws {
        let projected = try ProjectionRunner.project(output, as: kind)
        try ProjectionRenderDispatcher.render(
            projected,
            options: options,
            showProjectionDiagnostics: showProjectionDiagnostics
        )
    }
}
