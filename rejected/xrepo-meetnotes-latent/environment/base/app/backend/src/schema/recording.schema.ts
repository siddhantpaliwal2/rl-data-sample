// Type-only surface used by the search service. The runtime validator lives in
// the full backend; this isolated copy needs only the inferred query shape.
export type RecordingSearchQuery = {
  q: string;
  mode: "keyword" | "semantic" | "hybrid";
  limit: number;
};
