//
//  GeminiService.swift
//  LumiReader
//
//  Created by Shi on 2023/10/30.
//

import Foundation
import SwiftUI // Import SwiftUI

enum GeminiServiceError: Error {
    case invalidResponseType // 响应不是 HTTPURLResponse
    case httpError(statusCode: Int) // HTTP 状态码非 200，附带状态码
    case apiError(message: String) // API 返回的错误信息
    case invalidAPIKey // API Key 无效或未设置
    case emptyResponse // API 返回空内容
    case unknown(Error) // 其他未知错误
    case networkError(String) // Network error with description
}

struct GeminiService {
    // Update apiUrl to the streaming Gemini endpoint
    private static let apiUrl = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse")!
    
    static func summarizeArticles(articles: [[String: String]], apiKey: String, summaryPrompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use Encodable structs for summarizeArticles request body
        let summarizeRequestBody = ChatCompletionRequestBody(
            contents: [
                Content(
                    role: "user",
                    parts: [
                        Part(text: "请以Markdown格式返回以下内容的总结:\n\n\(articles)\n\n总结要求:\(summaryPrompt)")
                    ]
                )
            ],
            generationConfig: GenerationConfig(
                temperature: 0.3,
                topK: 30,
                topP: 0.7
            ),
            safetySettings: nil // Or specify safety settings if needed for summarization
        )

        request.httpBody = try JSONEncoder().encode(summarizeRequestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponseType
        }
        
        guard httpResponse.statusCode == 200 else {
            // Attempt to read error body if available (common for non-200)
            if let errorBodyString = String(data: data, encoding: .utf8) {
                throw GeminiServiceError.apiError(message: "HTTP Status Code: \(httpResponse.statusCode), Body: \(errorBodyString)")
            } else {
                throw GeminiServiceError.httpError(statusCode: httpResponse.statusCode)
            }
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiServiceError.emptyResponse // Or a more specific parsing error if needed
        }

        return text
    }

    static func chatWithGemini(
        articleContent: String,
        history: [ChatMessage],
        newMessage: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        guard !apiKey.isEmpty else {
            throw GeminiServiceError.invalidAPIKey
        }
        
        // 1. 构建内容数组
        var contents: [Content] = []
        
        // 2. 添加历史对话 (如果 history 数组不为空)
        // 这个 for 循环天然支持空数组，无需额外判断
        for message in history { // 注意：移除了 .dropLast() 以包含所有历史
            let role = message.sender == .user ? "user" : "model"
            contents.append(
                Content(role: role, parts: [Part(text: message.content)])
            )
        }
        
        // 3. 构建包含文章和新问题的用户消息
        // 为了让提示词更清晰，我们可以根据历史是否存在，稍微调整文本
        let historyPreamble = history.isEmpty ? "你是一个文章问答助手。" : "请结合之前的对话，"

        let userMessageText = """
        \(historyPreamble)现在基于以下文章内容，用中文来回答我的问题。

        ---
        文章内容:
        \(articleContent)
        ---

        我的问题:
        \(newMessage)
        """
        
        contents.append(
            Content(role: "user", parts: [Part(text: userMessageText)])
        )
        
        // 4. 构建请求体
        let requestBody = ChatCompletionRequestBody(
            contents: contents,
            generationConfig: GenerationConfig(
                temperature: 0.3,
                topK: 30,
                topP: 0.7
                // maxOutputTokens: 50000 // Optional
            ),
             safetySettings: [
                 SafetySetting(
                     category: "HARM_CATEGORY_HARASSMENT",
                     threshold: "BLOCK_NONE"
                 ),
                 SafetySetting(
                     category: "HARM_CATEGORY_HATE_SPEECH",
                     threshold: "BLOCK_NONE"
                 ),
                 SafetySetting(
                     category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                     threshold: "BLOCK_NONE"
                 ),
                 SafetySetting(
                     category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                     threshold: "BLOCK_NONE"
                 )
             ]
        )
        
        // Encode the request body struct
        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
             throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request body"])
        }
        
        // Print the encoded JSON body for debugging
        if let jsonString = String(data: httpBody, encoding: .utf8) {
            print("Sending Request Body:\n\(jsonString)")
        } else {
            print("Failed to convert HTTP body to string for logging.")
        }
        
        var request = URLRequest(url: apiUrl.appending(queryItems: [URLQueryItem(name: "key", value: apiKey)]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody // Assign the encoded body to the request
        request.timeoutInterval = 60
        
        // Use URLSession.shared.bytes for streaming
         return AsyncThrowingStream<String, Error> { continuation in
             Task {
                 do {
                     let (bytes, response) = try await URLSession.shared.bytes(for: request)
                     
                     guard let httpResponse = response as? HTTPURLResponse else {
                         continuation.finish(throwing: GeminiServiceError.invalidResponseType)
                         return
                     }
                     
                     guard httpResponse.statusCode == 200 else {
                         // Attempt to read and decode the error body
                         var errorData = Data()
                         for try await byte in bytes {
                             errorData.append(byte)
                         }

                         if let decodedError = try? JSONDecoder().decode(GeminiAPIErrorResponse.self, from: errorData) {
                             print("API Error: Status Code \(httpResponse.statusCode), Message: \(decodedError.error.message)")
                             continuation.finish(throwing: GeminiServiceError.apiError(message: decodedError.error.message))
                         } else if let errorBodyString = String(data: errorData, encoding: .utf8) {
                             // Log JSON decoding failure before falling back
                             print("Failed to decode API error JSON, falling back to raw body string.")
                             // Fallback to raw string if JSON decoding fails
                             print("HTTP Error: Status Code \(httpResponse.statusCode), Body: \(errorBodyString)")
                             continuation.finish(throwing: GeminiServiceError.apiError(message: "HTTP Status Code: \(httpResponse.statusCode), Body: \(errorBodyString)"))
                         } else {
                             // Fallback to just status code if no body or decoding fails
                             print("HTTP Error: Status Code \(httpResponse.statusCode), Failed to decode error body.")
                             continuation.finish(throwing: GeminiServiceError.httpError(statusCode: httpResponse.statusCode))
                         }
                          return
                     }
                     
                     // Process streaming bytes line by line
                     for try await line in bytes.lines {
                          // Each line from the stream is a JSON chunk (or [DONE]) prefixed with 'data: '
                          if line.starts(with: "data:") {
                              let jsonString = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                              
                              if jsonString == "[DONE]" {
                                  continuation.finish()
                                  return
                              }
                              
                              // Print the jsonString for debugging
                            //   print("Received JSON Chunk:\n\(jsonString)")
                              
                              if let jsonData = jsonString.data(using: .utf8) {
                                  do {
                                      // Decode the small JSON chunk for each data line
                                      let streamResponse = try JSONDecoder().decode(GeminiStreamResponse.self, from: jsonData)
                                      // Extract text from the correct path in the decoded struct
                                      if let candidates = streamResponse.candidates, let firstCandidate = candidates.first, let content = firstCandidate.content, let parts = content.parts, let firstPart = parts.first, let text = firstPart.text {
                                          continuation.yield(text)
                                      }
                                      
                                      // Check if the response indicates the end of the stream
                                      if let candidates = streamResponse.candidates, let firstCandidate = candidates.first, firstCandidate.finishReason == "STOP" {
                                        //   print("Received finishReason: STOP. Finishing stream.")
                                          continuation.finish()
                                          return // Exit the loop after finishing
                                      }
                                      
                                  } catch {
                                      // Log JSON decoding error for a single chunk but continue streaming
                                      print("JSON decoding error for a chunk: \(error). Json String: \(jsonString)")
                                      // Decide if a single chunk error should stop the whole stream
                                      // continuation.finish(throwing: error) // Option: Stop stream on any decoding error
                                  }
                              }
                          } else if !line.isEmpty { // Log unexpected lines that don't start with 'data:'
                              print("Received unexpected line in stream: \(line)")
                          }
                     }
                     
                     // If the loop finishes, it means the stream ended (either [DONE] received or connection closed)
                     print("Bytes stream processing loop finished.")
                     
                     // If the loop finishes without [DONE] (e.g., network issue, server error), finish the stream
                     // Only finish if [DONE] was NOT received (checked inside the loop)
                     // If [DONE] was received, continuation.finish() was already called.
                     // If we reached here because the connection closed without [DONE], it's an unexpected end.
                     // Let's add a flag to track if [DONE] was processed.
                     // *** Correction: Continuation should finish when the loop exits unless an error happened before.***
                     // The previous logic was mostly correct for unexpected end after processing lines.
                     continuation.finish(throwing: GeminiServiceError.unknown(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stream ended unexpectedly before [DONE] signal."]))) // Or a more specific error
 
                 } catch {
                     // Handle errors from URLSession.shared.bytes (e.g., network issues)
                     await MainActor.run { // Ensure UI updates/error handling on main thread
                         let specificError: GeminiServiceError
                         print("Error caught in GeminiService Task: \(error)")
                         if let urlError = error as? URLError {
                              specificError = .networkError(urlError.localizedDescription)
                         } else if let geminiError = error as? GeminiServiceError {
                              specificError = geminiError
                         } else {
                              specificError = .unknown(error)
                         }
                         continuation.finish(throwing: specificError)
                     }
                 }
             }
         }
    }

    // Add the non-streaming chat function
    static func chatWithGeminiNonStreaming(
        articleContent: String,
        history: [ChatMessage],
        newMessage: String,
        apiKey: String
    ) async throws -> String {
        
        guard !apiKey.isEmpty else {
            throw GeminiServiceError.invalidAPIKey
        }
        
        // Use the non-streaming API endpoint
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Set a reasonable timeout

        // Construct contents array using Encodable structs, similar to chatWithGemini
        var contents: [Content] = []
        
        // Add chat history
        for message in history.dropLast() {
            let role = message.sender == .user ? "user" : "model"
            contents.append(
                Content(
                    role: role,
                    parts: [
                        Part(text: message.content)
                    ]
                )
            )
        }
        
        // Add the new user message including article context and prompts
        // Keep the same prompt structure as the streaming version
        let userMessageText = "基于以下文章内容回复我的问题，请用中文。文章内容：\n\n\(articleContent)\n\n我的问题：\n\(newMessage)"
        
        contents.append(
            Content(
                role: "user",
                parts: [
                    Part(text: userMessageText)
                ]
            )
        )
        
        // Construct the request body struct
        let requestBody = ChatCompletionRequestBody(
            contents: contents,
            generationConfig: GenerationConfig(
                temperature: 0.3,
                topK: 30,
                topP: 0.7
            ),
             safetySettings: [
                 SafetySetting(
                     category: "HARM_CATEGORY_HARASSMENT",
                     threshold: "BLOCK_NONE"
                 ),
                 SafetySetting(
                     category: "HARM_CATEGORY_HATE_SPEECH",
                     threshold: "BLOCK_NONE"
                 ),
                 SafetySetting(
                     category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                     threshold: "BLOCK_NONE"
                 ),
                 SafetySetting(
                     category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                     threshold: "BLOCK_NONE"
                 )
             ]
        )
        
        // Encode the request body struct
        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
             throw NSError(domain: "GeminiService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request body"])
        }
        
        // Print the encoded JSON body for debugging
        // if let jsonString = String(data: httpBody, encoding: .utf8) {
        //     // print("Sending Non-Streaming Request Body:\n\(jsonString)")
        // } else {
        //     print("Failed to convert HTTP body to string for logging.")
        // }
        
        request.httpBody = httpBody // Assign the encoded body to the request
        
        // Perform the non-streaming request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponseType
        }
        
        guard httpResponse.statusCode == 200 else {
             // Attempt to read error body if available
             if let errorBodyString = String(data: data, encoding: .utf8) {
                 // Try decoding as GeminiAPIErrorResponse first
                 if let decodedError = try? JSONDecoder().decode(GeminiAPIErrorResponse.self, from: data) {
                      print("API Error (Non-Streaming): Status Code \(httpResponse.statusCode), Message: \(decodedError.error.message)")
                      throw GeminiServiceError.apiError(message: decodedError.error.message)
                 } else {
                     // Fallback to raw string if JSON decoding fails
                     print("HTTP Error (Non-Streaming): Status Code \(httpResponse.statusCode), Body: \(errorBodyString)")
                     throw GeminiServiceError.apiError(message: "HTTP Status Code: \(httpResponse.statusCode), Body: \(errorBodyString)")
                 }
             } else {
                 // Fallback to just status code if no body or decoding fails
                 print("HTTP Error (Non-Streaming): Status Code \(httpResponse.statusCode), Failed to decode error body.")
                 throw GeminiServiceError.httpError(statusCode: httpResponse.statusCode)
             }
        }
        
        // Parse the non-streaming JSON response, similar to summarizeArticles
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            
            // Log the raw response data if parsing fails
            if let rawResponseString = String(data: data, encoding: .utf8) {
                 print("Failed to parse Gemini non-streaming response. Raw data:\n\(rawResponseString)")
            } else {
                 print("Failed to parse Gemini non-streaming response. Raw data not convertible to string.")
            }
            
            throw GeminiServiceError.emptyResponse // Or a more specific parsing error
        }
        
        return text
    }
}

// Helper structs for encoding/decoding API requests/responses

struct ChatCompletionRequestBody: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig?
    let safetySettings: [SafetySetting]?
}

struct Content: Encodable {
    let role: String
    let parts: [Part]
}

struct Part: Encodable {
    let text: String
}

struct GenerationConfig: Encodable {
    let temperature: Double?
    let topK: Int?
    let topP: Double?
    // let maxOutputTokens: Int?
}

struct SafetySetting: Encodable {
    let category: String
    let threshold: String
}

// Decodable structs for streaming API response (adjust according to Gemini API response structure)
struct StreamCompletionResponse: Decodable {
    let choices: [StreamChoice]? // choices might be optional/empty on some responses
    let promptFeedback: PromptFeedback? // Add prompt feedback struct if needed
}

struct StreamChoice: Decodable {
    let delta: StreamDelta?
    // Add other fields like index if needed
}

struct StreamDelta: Decodable {
    let content: String?
}

struct PromptFeedback: Decodable {
    let safetyRatings: [SafetyRating]?
    let blockReason: String? // Assuming blockReason might be in promptFeedback
    // Add other feedback fields if needed
}

struct SafetyRating: Decodable {
    let category: String?
    let probability: String?
    // let blocked: Bool? // For newer API versions
}

struct GeminiCitationMetadata: Decodable {
    let citationSources: [GeminiCitationSource]?
}

struct GeminiCitationSource: Decodable {
    let startIndex: Int?
    let endIndex: Int?
    let uri: String?
    let license: String?
}

struct GeminiStreamResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent?
    let finishReason: String?
}

struct GeminiContent: Decodable {
    let parts: [GeminiPart]?
}

struct GeminiPart: Decodable {
    let text: String?
}

// Structs for decoding API error responses
struct GeminiAPIErrorResponse: Decodable {
    let error: APIError
}

struct APIError: Decodable {
    let code: Int
    let message: String
    let status: String
} 
 