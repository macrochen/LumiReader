//
//  Settings+CoreDataProperties.swift
//  LumiReader
//
//  Created by jolin on 2025/6/1.
//
//

import Foundation
import CoreData


extension Settings {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Settings> {
        return NSFetchRequest<Settings>(entityName: "Settings")
    }

    @NSManaged public var apiKey: String?
    @NSManaged public var batchSummaryPrompt: String?
    @NSManaged public var googleDriveAccessToken: String?
    @NSManaged public var googleDriveRefreshToken: String?

}

extension Settings : Identifiable {

}
