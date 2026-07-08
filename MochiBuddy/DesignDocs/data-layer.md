# Data Layer

> Part of [App Architecture](app-architecture.md)
>
> Reference implementation: a shared data-layer module (referred to below as `ContentKit`).

The data layer abstracts external data sources (API, DB, Cache) and provides domain models to the rest of the application. It consists of **Repositories**, a **Networking Stack** (NetworkClient, Services, DTOs), and **Mappers**.

---

## Repository

The main role of a repository is to **abstract the external data source** (API, DB, etc.) and offer an API aligned with domain business logic. A repository must not expose data types specific to the external source or bring in 3rd party library definitions.

**Mistakes to avoid:**

- Repository exposes DTOs to the outside
- DTOs are used for more than one source
- Repository defined around specific API endpoints instead of domain entities and higher logical concepts

**Implementation pattern:**

```swift
// ArticleRepository.swift

public protocol ArticleRepository {
    func fetchArticlesMetadata(startIndex: UInt, limit: UInt) async throws -> [ArticleSummary]
    func fetchArticleDetails(articleId: Int, ...) async throws -> ArticleDetail
    func fetchArticleData(articleId: Int) async throws -> ArticleData
    func updateArticleData(articleData: MutableArticleData, ...) async throws
    func deleteArticle(articleId: Int) async throws
    // ...
}

public class ArticleRepositoryAPI: ArticleRepository {
    private let networkClient: NetworkClient
    private let relatedContentProvider: RelatedContentProvider

    public init(networkClient: NetworkClient, relatedContentProvider: RelatedContentProvider) {
        self.networkClient = networkClient
        self.relatedContentProvider = relatedContentProvider
    }

    public func fetchArticleData(articleId: Int) async throws -> ArticleData {
        let config = ArticleService.articleData(articleId: articleId)
        let dto: ArticleDataDTO = try await networkClient.jsonTask(configuration: config)
        return try ArticleData(dto: dto)
    }
}
```

**Repository with caching:**

```swift
// ReportsRepository.swift

protocol ReportsRepository {
    func getLatestSummaries(config: SummaryConfig) async throws -> ReportStats
    func getSummaries(config: SummaryConfig) async throws -> ReportStats
}

final class ReportsRepositoryImpl: ReportsRepository {
    private let networkClient: NetworkClient
    private let categoryStore: CategoryStore
    private let cache: ReportsCache

    func getSummaries(config: SummaryConfig) async throws -> ReportStats {
        let cacheKey = createCacheStatsKey(basedOn: config)
        if let stats = cache.getStats(for: cacheKey) {
            return stats
        }
        return try await getStats(config: config)
    }

    private func getStats(config: SummaryConfig) async throws -> ReportStats {
        let configuration = ReportsService.summaries(...)
        let statsDTO: [SingleDateStatsDTO] = try await networkClient.jsonTask(configuration: configuration)
        let stats = try statsDTO.map { try SingleDateStatsMapper.map($0) }
        cache.saveStats(reportStats, for: key)
        return reportStats
    }
}
```

**Key guidelines:**

- Repositories should define their own errors — one error enum per layer, mapped at boundaries:

```swift
// Repository errors
enum RecordRepositoryError: Error {
    case recordDetailsNotFound
}

// Store errors (higher level, may wrap repository errors)
enum ContentDataStoreError: Error {
    case contentNotFound
    case errorLoadingContent
}
```

- A protocol is not always needed initially—add it when testing or multiple implementations require it.
- Repositories can share in-memory models across views (since they are injected).
- Use a repository directly in a ViewModel when fetching data for a specific model, data is local, and no aggregation is needed.
- Repositories should leverage Swift's `async/await` concurrency. Prefer `throws` over optional return types—an operation either succeeds with a value or fails with a meaningful error. Using other reactive systems (e.g. Combine) at the repository level is discouraged to keep the API simple and predictable.
- **Mapping is the repository's responsibility.** The repository calls the Service, receives DTOs, and maps them to domain models before returning. An API Service must never perform mapping—its sole concern is constructing the correct request configuration.

---

## Networking Stack

Since most repositories are API implementations, the networking stack consists of:

### NetworkClient

An injected client with preconfigured host and credentials. Always injected into the API repository so we are not concerned with environment or credentials.

- Enables **unit testing** via saved JSON responses and a mock network client from a shared unit-test module.
- Makes development before the API is available simple—write final versions of all layers.

Reference: your networking utility library's `NetworkClient`.

### Service / RequestConfiguration

Defines the configuration for each endpoint call using an enum. Service components work with DTOs.

```swift
// Network/ArticleService/ArticleService.swift

enum ArticleService: RequestConfiguration {
    case details(articleId: Int, maxChartSize: UInt?, maxPolylineSize: UInt?, splitType: String?, metrics: [String]?)
    case articleData(articleId: Int)
    case delete(articleId: Int)
    case weather(articleId: Int)
    // ...

    var method: HTTPMethod {
        switch self {
        case .delete: return .delete
        default: return .get
        }
    }

    var path: String {
        switch self {
        case .details(let articleId, _, _, _, _): return "\(articleId)/details"
        case .articleData(let articleId): return "\(articleId)"
        case .weather(let articleId): return "\(articleId)/weather"
        // ...
        }
    }
}
```

### DTOs

Simple data types close to JSON. Keep dates as strings, enums as strings—the mapper handles transformation.

```swift
// Network/ArticleService/Generated DTOs/WeatherInfoDTO.swift

struct WeatherInfoDTO: Codable {
    public let issueDate: Date?
    public let temp: Int?
    public let apparentTemp: Int?
    public let windDirection: Int?
    public let windSpeed: Int?
    public let latitude: Double?
    public let longitude: Double?
    public let stationName: String?
    public let typeDescription: String?
}
```

### Mapper

Transforms DTOs into domain models. Uses the `DTOMapper` protocol from `PlatformUtil`:

```swift
// PlatformUtil/Mapper/DTOMapper.swift

public protocol DTOMapper {
    associatedtype DTO
    associatedtype Model

    static func map(_ from: DTO) throws -> Model
    static func map(_ from: DTO?) throws -> Model
    static func mapLossyArray(_ from: [DTO]) -> [Model]
    static func mapArray(_ from: [DTO]) throws -> [Model]
}
```

Implementation example:

```swift
// Mappers/SummaryMapper.swift

public struct SummaryMapper: DTOMapper {
    public typealias DTO = SummaryDTO
    public typealias Model = Summary

    public static func map(_ from: SummaryDTO) throws -> Summary {
        let allMetrics = try from.allMetrics?.metricsMap.mapValues {
            try $0.map { try MetricMapper.map($0) }
        }
        return Summary(allMetrics: allMetrics,
                       itemList: try from.itemList?.payload?.itemList.map {
                           try ReportItemMapper.map($0)
                       })
    }
}
```

```swift
// Mappers/SingleDateStatsMapper.swift

struct SingleDateStatsMapper: DTOMapper {
    typealias DTO = SingleDateStatsDTO
    typealias Model = SingleDateStatsData

    static func map(_ from: SingleDateStatsDTO) throws -> SingleDateStatsData {
        var stats: [String: [String: StatsData]] = [:]
        for (key, value) in from.stats {
            stats[key] = try value.mapValues { try StatsDataMapper.map($0) }
        }
        return SingleDateStatsData(
            date: Date.from(iso8601LocalRepresentation: from.date),
            countOfItems: from.countOfItems,
            stats: stats
        )
    }
}
```

### API Repository Fetch Flow

1. Use the **Service** to generate a request configuration based on parameters.
2. Use the **NetworkClient** to make the request.
3. Use the **Mapper** to transform the DTO response into domain models.

---

## Project Structure (reference)

```
Sources/ContentKit/
├── Model/                         # Domain models (immutable structs)
│   ├── ArticleData/
│   ├── ArticleDetail.swift
│   ├── WeatherInfo.swift
│   └── ...
├── Network/                       # External gateway (API)
│   ├── ArticleService/            # Request configurations (enum)
│   │   ├── ArticleService.swift
│   │   └── Generated DTOs/        # DTO definitions
│   │       ├── WeatherInfoDTO.swift
│   │       ├── ArticleDataDTO.swift
│   │       └── ...
│   ├── SearchService/
│   ├── MediaService/
│   └── Common/                    # Shared network utilities
├── Mappers/                       # DTO → Domain Model transformations
│   ├── SummaryMapper.swift
│   ├── WeatherInfoMapper.swift
│   └── ...
├── ArticleRepository.swift        # Repository protocol + API implementation
├── SearchRepository.swift
├── MediaRepository.swift
└── ...
```

---

## Reference

- [App Architecture](app-architecture.md)
- [Domain Layer — Stores](domain-layer.md)
