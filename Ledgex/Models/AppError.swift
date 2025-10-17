import Foundation

struct AppError: Identifiable, Error, LocalizedError {
    let id = UUID()
    let title: String
    let message: String
    let underlyingError: Error?

    init(title: String = "Something went wrong", message: String, underlyingError: Error? = nil) {
        self.title = title
        self.message = message
        self.underlyingError = underlyingError
    }

    var errorDescription: String? { message }

    static func make(from error: Error, fallbackTitle: String = "Something went wrong", fallbackMessage: String = "Please try again.") -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if let appErrorConvertible = error as? AppErrorConvertible {
            return appErrorConvertible.appError
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return AppError(title: fallbackTitle, message: description, underlyingError: error)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return AppError(title: "Network Unavailable", message: "The connection appears to be offline. Check your network and try again.", underlyingError: error)
        }

        return AppError(title: fallbackTitle, message: fallbackMessage, underlyingError: error)
    }
}

protocol AppErrorConvertible {
    var appError: AppError { get }
}
