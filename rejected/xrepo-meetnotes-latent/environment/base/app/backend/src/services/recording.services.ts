// Offline test double for the recordings data source.
//
// The real service reads recordings from Firestore. This isolated copy of the
// search layer never touches the network: `listRecordings` returns whatever the
// current test has staged via `__setRecordings`. The shape mirrors the fields
// the search service actually reads (id, title, status, transcript.fullText).

export type AppRecording = {
  id: string;
  title: string;
  status: string;
  transcript: { fullText: string };
};

let stagedRecordings: AppRecording[] = [];

export const __setRecordings = (recordings: AppRecording[]) => {
  stagedRecordings = recordings;
};

export const listRecordings = async (
  _userId: string,
): Promise<AppRecording[]> => {
  return stagedRecordings;
};
