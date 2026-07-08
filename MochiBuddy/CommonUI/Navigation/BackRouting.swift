//
//  BackRouting.swift
//  MochiBuddy
//
//  CommonUI — the smallest routing capability: popping back. Screens that
//  only ever navigate back (e.g. ManageLists, reachable from both the You
//  and Tasks flows) depend on this instead of a feature-specific router.
//

@MainActor
protocol BackRouting: AnyObject {
    func navigateBack()
}
