import Foundation

// MARK: - Top-level JSONL line

struct JSONLLine: Decodable {
    let type: String?
    let message: AssistantMessage?
    let requestId: String?
}

// MARK: - Assistant message

struct AssistantMessage: Decodable {
    let id: String?
    let model: String?
    let role: String?
    let usage: TokenUsage?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case id, model, role, usage
        case stopReason = "stop_reason"
    }
}

// MARK: - Token usage

struct TokenUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}
