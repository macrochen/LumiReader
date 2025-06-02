//
//  Chat+CoreDataProperties.swift
//  LumiReader
//
//  Created by jolin on 2025/6/1.
//
//

import Foundation
import CoreData


extension Chat {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Chat> {
        return NSFetchRequest<Chat>(entityName: "Chat")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var article: Article?
    @NSManaged public var messages: NSSet?

}

// MARK: Generated accessors for messages
extension Chat {

    @objc(addMessagesObject:)
    @NSManaged public func addToMessages(_ value: Message)

    @objc(removeMessagesObject:)
    @NSManaged public func removeFromMessages(_ value: Message)

    @objc(addMessages:)
    @NSManaged public func addToMessages(_ values: NSSet)

    @objc(removeMessages:)
    @NSManaged public func removeFromMessages(_ values: NSSet)

}

extension Chat : Identifiable {

}
