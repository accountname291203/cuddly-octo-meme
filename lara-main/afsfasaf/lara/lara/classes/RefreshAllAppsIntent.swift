//
//  RefreshAllAppsIntent.swift
//  lara
//
//  Shortcuts integration — "Refresh All Apps" intent
//  Runs the full exploit chain and installs pending SideStore profiles via misagent.
//

import AppIntents
import Foundation

#if !DISABLE_REMOTECALL

@available(iOS 16.0, *)
struct RefreshAllAppsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh All Apps"
    static var description = IntentDescription(
        "Runs the lara exploit chain and installs pending SideStore provisioning profiles via misagent (RemoteCall). Works fully offline — no internet required for profile installation.",
        categoryName: "SideStore"
    )
    
    // The exploit chain requires lara's process to be running,
    // so we need iOS to launch the app when the shortcut is triggered.
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true
    
    /// Optional: force re-run even if exploit is already active
    @Parameter(title: "Force Re-initialize", default: false)
    var forceReinit: Bool
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let mgr = await MainActor.run { laramgr.shared }
        
        // Pre-check: make sure offsets are available
        let hasOffsets = await MainActor.run { mgr.hasOffsets }
        if !hasOffsets {
            // Try to init offsets (these are compiled-in for supported devices)
            await MainActor.run {
                init_offsets()
                offsets_init()
                mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
            }
            let stillNoOffsets = await MainActor.run { !mgr.hasOffsets }
            if stillNoOffsets {
                return .result(value: "❌ No offsets available. Open lara manually and fetch the kernelcache first (requires network once).")
            }
        }
        
        // Step 1: Run the kernel exploit (darksword)
        let exploitReady = await MainActor.run { mgr.dsready }
        if !exploitReady || forceReinit {
            let exploitSuccess = await runExploit(mgr: mgr)
            if !exploitSuccess {
                return .result(value: "❌ Exploit failed. Device may not be supported or a debugger is attached.")
            }
        }
        
        // Step 2: Initialize hybrid system (VFS + SBX escape)
        let hybridReady = await MainActor.run { mgr.vfsready && mgr.sbxready }
        if !hybridReady || forceReinit {
            let hybridSuccess = await initHybrid(mgr: mgr)
            if !hybridSuccess {
                return .result(value: "❌ Hybrid init failed (VFS/SBX). Exploit succeeded but system init failed.")
            }
        }
        
        // Step 3: Initialize RemoteCall on SpringBoard
        let rcReady = await MainActor.run { mgr.rcready }
        if !rcReady || forceReinit {
            let rcSuccess = await initRemoteCall(mgr: mgr)
            if !rcSuccess {
                return .result(value: "❌ RemoteCall init failed on SpringBoard.")
            }
        }
        
        // Step 4: Run SideStore refresh (install pending profiles via misagent)
        let refreshResult = await refreshSideStore(mgr: mgr)
        
        // Step 5: Clean up — destroy RemoteCall to leave the system stable
        await destroyRemoteCall(mgr: mgr)
        
        return .result(value: refreshResult)
    }
    
    // MARK: - Exploit Chain Steps
    
    private func runExploit(mgr: laramgr) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                offsets_init()
                mgr.run { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    private func initHybrid(mgr: laramgr) async -> Bool {
        // Run VFS and SBX in parallel (same as the "Initialize System" button)
        async let vfsResult = initVFS(mgr: mgr)
        async let sbxResult = initSBX(mgr: mgr)
        
        let (vfs, sbx) = await (vfsResult, sbxResult)
        return vfs && sbx
    }
    
    private func initVFS(mgr: laramgr) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                mgr.vfsinit { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    private func initSBX(mgr: laramgr) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                mgr.sbxescape { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    private func initRemoteCall(mgr: laramgr) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                mgr.rcinit(process: "SpringBoard", migbypass: false) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    private func refreshSideStore(mgr: laramgr) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = mgr.sbProc
                guard let proc = proc else {
                    continuation.resume(returning: "❌ RemoteCall process is nil")
                    return
                }
                
                var lastStatus: String = ""
                let result = rc_sidestore_refresh(proc) { progress, status in
                    if let status = status as String? {
                        lastStatus = status
                    }
                }
                
                if result > 0 {
                    continuation.resume(returning: "✅ Refreshed \(result) app profiles!")
                } else if result == 0 {
                    continuation.resume(returning: "⚠️ No pending profiles found. Open SideStore and trigger a refresh first, then run this again to install the profiles.")
                } else {
                    continuation.resume(returning: "❌ Refresh failed (error: \(result)). \(lastStatus)")
                }
            }
        }
    }
    
    private func destroyRemoteCall(mgr: laramgr) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                mgr.rcdestroy {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, *)
struct LaraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshAllAppsIntent(),
            phrases: [
                "Refresh all apps with \(.applicationName)",
                "Refresh apps in \(.applicationName)",
                "\(.applicationName) refresh all apps",
                "Install profiles with \(.applicationName)",
                "Refresh SideStore with \(.applicationName)"
            ],
            shortTitle: "Refresh All Apps",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}

#endif
