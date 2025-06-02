//
//  Article+CoreDataProperties.swift
//  LumiReader
//
//  Created by jolin on 2025/6/1.
//
//

import Foundation
import CoreData


extension Article {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Article> {
        return NSFetchRequest<Article>(entityName: "Article")
    }

    @NSManaged public var content: String?
    @NSManaged public var importDate: Date?
    @NSManaged public var link: String?
    @NSManaged public var title: String?
    @NSManaged public var batchSummaries: NSSet?
    @NSManaged public var chat: Chat?

}

// MARK: Generated accessors for batchSummaries
extension Article {

    @objc(addBatchSummariesObject:)
    @NSManaged public func addToBatchSummaries(_ value: BatchSummary)

    @objc(removeBatchSummariesObject:)
    @NSManaged public func removeFromBatchSummaries(_ value: BatchSummary)

    @objc(addBatchSummaries:)
    @NSManaged public func addToBatchSummaries(_ values: NSSet)

    @objc(removeBatchSummaries:)
    @NSManaged public func removeFromBatchSummaries(_ values: NSSet)

}

extension Article : Identifiable {

}
