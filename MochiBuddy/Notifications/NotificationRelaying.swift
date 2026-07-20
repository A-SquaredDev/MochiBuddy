//
//  NotificationRelaying.swift
//  MochiBuddy
//
//  The tiny seam ViewModels use to poke the scheduler after a mutation,
//  so their tests stub one method instead of the whole orchestrator.
//

import Foundation

@MainActor
protocol NotificationRelaying: AnyObject {
    func requestRelay(_ trigger: RelayTrigger)
}

extension NotificationOrchestrator: NotificationRelaying {}
