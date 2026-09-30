@attached(member, names: named(configuration))
@attached(extension, conformances: HLSCatalogDefining)
public macro HLSCatalogDefinition(maximumEntries: Int = 512, maximumSnapshotBytes: Int = 1_048_576) =
    #externalMacro(module: "InnoNetworkStreamMacros", type: "HLSWorkflowDefinitionMacro")

public protocol HLSCatalogDefining { static func configuration() throws -> HLSMediaCatalogConfiguration }
public extension HLSCatalogDefining {
    /// Constructs without reading/writing. Restore and mutation are explicit.
    static func makeCatalog(persistence: (any HLSMediaCatalogPersisting)? = nil) throws -> HLSMediaCatalog {
        HLSMediaCatalog(configuration: try configuration(), persistence: persistence)
    }
}
