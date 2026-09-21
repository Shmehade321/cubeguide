import Testing

/// Scene stress tests and live display-clock tests share the main run loop.
/// Serialize the whole family so synchronous exhaustive checks cannot consume
/// another test's wall-clock deadline while preventing its frame delivery.
@Suite(.serialized)
struct PresentationTests {}
