# 发布流程

发布由 tag 触发：推送 `v*` tag 后，GitHub Actions 会构建 Rust sidecar 与 Flutter Windows 应用，
产出免安装 zip 和 NSIS 安装包，写入 SHA-256 校验表，并创建 GitHub Release。

## 1. 整理更新记录

先看上一次发布以来的提交：

```powershell
git log "$(git describe --tags --abbrev=0)..HEAD" --pretty=format:"%h %s"
```

把面向用户的改动写进 `changeslog.md` 顶部，按以下约定：

- 标题必须是 `## <版本号> — <日期>`，版本号与 tag 去掉 `v` 后一致
- 开头用一两句话概括本版，再按「新增 / 修复 / 变更 / 移除 / 已知问题」分组，没有就省略
- 只写用户能感知的变化，不写内部重构、依赖调整和开发过程中的修复
- 保留 `### 校验` 与 `<!--CHECKSUMS-->`，打包时会替换成安装包哈希
- 版本之间不要写 `---`

## 2. 同步版本号

以下位置必须一起改成同一版本号：

- `island_app/pubspec.yaml` 的 `version`（形如 `0.2.0+1`，构建时会被 tag 覆盖，但保持文件一致便于本地排查）
- `island_app/lib/core/app_info.dart` 的 `appVersion`（设置页、诊断页与更新横幅显示）
- `island_service/Cargo.toml` 的 `version`（`update.check` 用它和线上版本比较，必须改）
- `installer/gudong.nsi` 的默认 `VERSION`（工作流会传 `-DVERSION` 覆盖，仅本地打包时生效）

改完 `Cargo.toml` 后运行 `cargo build --release` 刷新 `Cargo.lock`
（CI 用 `cargo build --locked`，锁文件不同步会直接失败）。`build.rs` 里 exe 的版本资源
已从 `CARGO_PKG_VERSION` 派生，不需要手改。

## 3. 提交并打 tag

```powershell
git add changeslog.md island_app/pubspec.yaml island_app/lib/core/app_info.dart `
  island_service/Cargo.toml island_service/Cargo.lock installer/gudong.nsi
git commit -m "chore(release): prepare v0.1.0"
git tag v0.1.0
git push origin main --tags
```

推送 tag 即触发 `.github/workflows/release.yml`。工作流也支持 `v0.2.0-beta.1` 这类预发布 tag，
会自动标记为 prerelease。

## 4. 检查产物

Release 包含：

- `gudong-<版本>-setup.exe` —— NSIS 安装包（当前用户安装，无需管理员权限）
- `gudong-<版本>-windows-x64.zip` —— 免安装压缩包

正文来自 `changeslog.md` 对应版本段落；找不到时退化为按提交类型自动生成。
zip 与安装包内置 MSVC 运行库，可在未安装 VC++ Redistributable 的机器上直接运行。
