// Offline test double for the embedding provider. The keyword search path never
// calls this; the semantic path is exercised only for the empty-result control.
export const generateEmbeddings = async (
  _chunks: Array<{ chunkIndex: number; text: string; tokenCount: number }>,
): Promise<Array<{ embedding: number[] }>> => {
  return [];
};
