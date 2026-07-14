// Offline test double for usage accounting. A no-op in the isolated harness.
export const incrementUsageMetrics = async (_args: {
  userId: string;
  aiRequestCount: number;
}): Promise<void> => {
  return;
};
