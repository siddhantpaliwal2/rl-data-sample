// Offline test double for the vector store. Returns no chunks, so the semantic
// control resolves to an empty result set without any network access.
export const searchUserChunks = async (_args: {
  userId: string;
  queryEmbedding: number[];
  limit: number;
}): Promise<Array<{ recordingId: string }>> => {
  return [];
};
