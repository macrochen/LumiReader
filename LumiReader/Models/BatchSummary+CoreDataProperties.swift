//
//  BatchSummary+CoreDataProperties.swift
//  LumiReader
//
//  Created by jolin on 2025/6/1.
//
//

import Foundation
import CoreData


extension BatchSummary {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BatchSummary> {
        return NSFetchRequest<BatchSummary>(entityName: "BatchSummary")
    }

    @NSManaged public var content: String?
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var articles: NSSet?

}

// MARK: Generated accessors for articles
extension BatchSummary {

    @objc(addArticlesObject:)
    @NSManaged public func addToArticles(_ value: Article)

    @objc(removeArticlesObject:)
    @NSManaged public func removeFromArticles(_ value: Article)

    @objc(addArticles:)
    @NSManaged public func addToArticles(_ values: NSSet)

    @objc(removeArticles:)
    @NSManaged public func removeFromArticles(_ values: NSSet)

}

extension BatchSummary : Identifiable {

}
