//
//  HTTPResponseValidator.swift
//  DuffyNetworking
//
//  Created by Joseph Duffy on 01/08/2026.
//


public protocol HTTPResponseValidator: Sendable {
    func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) async throws
}