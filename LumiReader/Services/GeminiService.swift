import Foundation


struct GeminiService {
    static func summarizeArticles(articles: [[String: String]], apiKey: String, summaryPrompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": "请以Markdown格式返回以下内容的总结:\n\n\(articles)\n\n总结要求:\(summaryPrompt)"
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "topK": 30,
                "topP": 0.7
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"])
        }

        return text
    }

    // Add the chatWithGemini function here
    static func chatWithGemini(articleContent: String, history: [ChatMessage], newMessage: String, apiKey: String) async throws -> AsyncThrowingStream<String, Error> {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)&alt=json&stream=true")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Prepare the contents for the API request
        var contents: [[String: Any]] = []

        // Add article content as the initial context
        contents.append([
            "parts": [
                ["text": "以下是文章内容，用于后续对话参考：\n\n\(articleContent)"]
            ]
        ])

        // Add chat history, mapping Sender enum to API roles
        for message in history {
            let role = message.sender == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [
                    ["text": message.content]
                ]
            ])
        }

        // Add the new user message
        contents.append([
            "role": "user",
            "parts": [
                ["text": newMessage]
            ]
        ])

        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topK": 30,
                "topP": 0.9
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Use AsyncThrowingStream to handle streaming response
        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
                    }

                    // Process streaming bytes
                    for try await line in bytes.lines {
                         // Each line from the stream is a JSON chunk
                         if let jsonData = line.data(using: .utf8),
                            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                            let candidates = json["candidates"] as? [[String: Any]],
                            let firstCandidate = candidates.first,
                            let content = firstCandidate["content"] as? [String: Any],
                            let parts = content["parts"] as? [[String: Any]] {

                            for part in parts {
                                if let text = part["text"] as? String {
                                    continuation.yield(text)
                                }
                            }
                        }
                    }
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
} 
