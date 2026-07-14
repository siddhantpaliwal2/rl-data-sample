import type { AppRecording } from "./recording.services";
import type { RecordingSearchQuery } from "../schema/recording.schema";
import { generateEmbeddings } from "./embedding.services";
import { listRecordings } from "./recording.services";
import { searchUserChunks } from "./qdrant.services";
import { incrementUsageMetrics } from "./usage.services";

type KeywordSearchResult = {
  recordingId: string;
  title: string;
  status: string;
  matchedFields: string[];
  textPreview: string;
};

const includesQuery = (value: unknown, query: string) => {
  return typeof value === "string" && value.toLowerCase().includes(query);
};

//----------------------------------------------------------------------------------------------------------------

const getTranscriptText = (recording: AppRecording) => {
  const transcript = recording.transcript.fullText;
  return typeof transcript === "string" ? transcript : "";
};

//----------------------------------------------------------------------------------------------------------------

const getTextPreview = (text: string, query: string) => {
  const index = text.toLowerCase().indexOf(query);

  if (index < 0) {
    return text.slice(0, 180);
  }

  return text.slice(Math.max(index - 60, 0), index + 120);
};

//----------------------------------------------------------------------------------------------------------------

const searchRecordingsByKeyword = (
  recordings: AppRecording[],
  query: string,
  limit: number,
) => {
  const normalizedQuery = query.toLowerCase();
  const results: KeywordSearchResult[] = [];

  recordings.forEach((recording) => {
    const transcript = getTranscriptText(recording);
    const matchedFields = [
      includesQuery(recording.title, normalizedQuery) ? "title" : "",
      includesQuery(transcript, normalizedQuery) ? "transcript" : "",
    ].filter(Boolean);

    if (!matchedFields.length) return;

    results.push({
      recordingId: recording.id,
      title: recording.title,
      status: recording.status,
      matchedFields,
      textPreview: getTextPreview(transcript || recording.title, normalizedQuery),
    });
  });

  return results.slice(0, limit);
};

//----------------------------------------------------------------------------------------------------------------

const searchRecordingsBySemantic = async (
  userId: string,
  query: string,
  limit: number,
  activeRecordingIds: Set<string>,
) => {
  if (!activeRecordingIds.size) {
    return [];
  }

  const queryEmbeddings = await generateEmbeddings([
    {
      chunkIndex: 0,
      text: query,
      tokenCount: Math.ceil(query.length / 4),
    },
  ]);
  const queryEmbedding = queryEmbeddings[0]?.embedding ?? [];

  await incrementUsageMetrics({
    userId,
    aiRequestCount: 1,
  });

  return searchUserChunks({
    userId,
    queryEmbedding,
    limit: Math.max(limit * 5, limit),
  }).then((results) =>
    results
      .filter((result) => activeRecordingIds.has(result.recordingId))
      .slice(0, limit),
  );
};

//----------------------------------------------------------------------------------------------------------------

// Searches recordings by keyword, semantic similarity, or both.
export const searchRecordings = async (
  input: RecordingSearchQuery & { userId: string },
) => {
  const recordings = await listRecordings(input.userId);
  const activeRecordingIds = new Set(recordings.map((recording) => recording.id));
  const keywordResults =
    input.mode === "semantic"
      ? []
      : searchRecordingsByKeyword(recordings, input.q, input.limit);
  const semanticResults =
    input.mode === "keyword"
      ? []
      : await searchRecordingsBySemantic(
          input.userId,
          input.q,
          input.limit,
          activeRecordingIds,
        );

  return {
    query: input.q,
    mode: input.mode,
    keywordResults,
    semanticResults,
  };
};
