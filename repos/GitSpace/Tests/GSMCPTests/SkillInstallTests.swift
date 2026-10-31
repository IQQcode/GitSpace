import Testing
import Foundation
import GSInfra
import GSMCP

/// skill 安装器（Story-1031-mcp W3）：安装/跳过/覆盖更新/保留用户文件。
@Suite("Skill Install")
struct SkillInstallTests {
    private func makeSource(version: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-skill-src-\(UUID().uuidString)", isDirectory: true)
        let skillDir = dir.appendingPathComponent("Skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir.appendingPathComponent("references"), withIntermediateDirectories: true)
        try """
        ---
        name: git-space
        description: 测试用
        version: \(version)
        ---
        内容
        """.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "工作流".write(to: skillDir.appendingPathComponent("references/workflows.md"), atomically: true, encoding: .utf8)
        return skillDir
    }

    private func makeTarget() -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitspace-skill-dst-\(UUID().uuidString)", isDirectory: true)
        return (
            dir.appendingPathComponent("git-space", isDirectory: true),
            dir.appendingPathComponent("manifest.json")
        )
    }

    @Test func installsWhenAbsent() throws {
        let source = try makeSource(version: "1.0.0")
        let (target, manifest) = makeTarget()

        let installed = try MCPSkillInstaller.installIfNeeded(
            sourceDirectory: source, targetDirectory: target, manifestFile: manifest
        )

        #expect(installed)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("references/workflows.md").path))
        #expect(MCPSkillInstaller.installedManifest(at: manifest)?.version == "1.0.0")
    }

    @Test func skipsWhenSameVersion() throws {
        let source = try makeSource(version: "1.0.0")
        let (target, manifest) = makeTarget()
        _ = try MCPSkillInstaller.installIfNeeded(sourceDirectory: source, targetDirectory: target, manifestFile: manifest)

        let second = try MCPSkillInstaller.installIfNeeded(
            sourceDirectory: source, targetDirectory: target, manifestFile: manifest
        )

        #expect(second == false)
    }

    @Test func updatesWhenVersionBumped() throws {
        let (target, manifest) = makeTarget()
        _ = try MCPSkillInstaller.installIfNeeded(
            sourceDirectory: try makeSource(version: "1.0.0"), targetDirectory: target, manifestFile: manifest
        )
        let newer = try makeSource(version: "1.1.0")

        let updated = try MCPSkillInstaller.installIfNeeded(
            sourceDirectory: newer, targetDirectory: target, manifestFile: manifest
        )

        #expect(updated)
        #expect(MCPSkillInstaller.installedManifest(at: manifest)?.version == "1.1.0")
    }

    @Test func preservesUserExtraFiles() throws {
        let (target, manifest) = makeTarget()
        _ = try MCPSkillInstaller.installIfNeeded(
            sourceDirectory: try makeSource(version: "1.0.0"), targetDirectory: target, manifestFile: manifest
        )
        let userNote = target.appendingPathComponent("my-notes.md")
        try "用户自己的文件".write(to: userNote, atomically: true, encoding: .utf8)

        _ = try MCPSkillInstaller.installIfNeeded(
            sourceDirectory: try makeSource(version: "2.0.0"), targetDirectory: target, manifestFile: manifest
        )

        #expect(FileManager.default.fileExists(atPath: userNote.path), "用户自加文件不得被删除")
    }
}