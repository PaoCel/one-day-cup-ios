// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TorneoMultipaloLogic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TorneoMultipaloLogic",
            targets: ["TorneoMultipaloLogic"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.10.0")
    ],
    targets: [
        .target(
            name: "TorneoMultipaloLogic",
            dependencies: [
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            path: "Torneo Multipalo",
            sources: [
                "Extensions/String+NomeGiocatore.swift",
                "App/FirebaseBootstrap.swift",
                "App/RuntimeSafety.swift",
                "Extensions/Firestore+Async.swift",
                "Models/AwardConfig.swift",
                "Models/Figurina.swift",
                "Models/EditionParticipation.swift",
                "Models/Match.swift",
                "Models/PenaltyMiss.swift",
                "Models/Player.swift",
                "Models/StandingsEntry.swift",
                "Models/Team.swift",
                "Models/TournamentStructure.swift",
                "Services/AwardStandingsBuilder.swift",
                "Services/MatchGoalkeeperResolver.swift",
                "Services/MatchPenaltySupport.swift",
                "Services/MatchStaffSupport.swift",
                "Services/StandingsCalculator.swift"
            ]
        ),
        .testTarget(
            name: "TorneoMultipaloLogicTests",
            dependencies: [
                "TorneoMultipaloLogic",
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ]
        )
    ]
)
