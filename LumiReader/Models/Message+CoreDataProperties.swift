//
//  Message+CoreDataProperties.swift
//  LumiReader
//
//  Created by jolin on 2025/6/1.
//
//

import Foundation
import CoreData


extension Message {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Message> {
        return NSFetchRequest<Message>(entityName: "Message")
    }

    @NSManaged public var content: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var isFromUser: Bool
    @NSManaged public var chat: Chat?

}

extension Message : Identifiable {

}
