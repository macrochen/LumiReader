//
//  PresetPrompt+CoreDataProperties.swift
//  LumiReader
//
//  Created by jolin on 2025/6/1.
//
//

import Foundation
import CoreData


extension PresetPrompt {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PresetPrompt> {
        return NSFetchRequest<PresetPrompt>(entityName: "PresetPrompt")
    }

    @NSManaged public var content: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var title: String?

}

extension PresetPrompt : Identifiable {

}
