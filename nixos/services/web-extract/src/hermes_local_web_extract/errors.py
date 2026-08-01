from hermes_local_web_extract.models import ExtractErrorCode


class ExtractException(Exception):
    def __init__(self, code: ExtractErrorCode, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class InvalidURLError(ExtractException):
    def __init__(self, message: str = "Invalid or disallowed URL.") -> None:
        super().__init__(ExtractErrorCode.INVALID_URL, message)


class BlockedAddressError(ExtractException):
    def __init__(self, message: str = "URL resolves to a blocked address.") -> None:
        super().__init__(ExtractErrorCode.BLOCKED_PRIVATE_ADDRESS, message)


class FetchTimeoutError(ExtractException):
    def __init__(self, message: str = "Request timed out.") -> None:
        super().__init__(ExtractErrorCode.FETCH_TIMEOUT, message)


class FetchError(ExtractException):
    def __init__(self, message: str = "Failed to fetch URL.") -> None:
        super().__init__(ExtractErrorCode.FETCH_ERROR, message)


class BodyTooLargeError(ExtractException):
    def __init__(self, message: str = "Response body exceeds size limit.") -> None:
        super().__init__(ExtractErrorCode.BODY_TOO_LARGE, message)


class UnsupportedContentTypeError(ExtractException):
    def __init__(self, content_type: str) -> None:
        super().__init__(
            ExtractErrorCode.UNSUPPORTED_CONTENT_TYPE,
            f"Unsupported content type: {content_type}",
        )


class ExtractionFailedError(ExtractException):
    def __init__(self, message: str = "Content extraction failed.") -> None:
        super().__init__(ExtractErrorCode.EXTRACTION_FAILED, message)


class RateLimitedError(ExtractException):
    def __init__(self, message: str = "Rate limit exceeded. Try again later.") -> None:
        super().__init__(ExtractErrorCode.RATE_LIMITED, message)
