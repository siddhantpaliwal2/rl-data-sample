export type RecordingStatus =
  | 'uploading'
  | 'uploaded'
  | 'transcribing'
  | 'transcribed'
  | 'summarizing'
  | 'embedding'
  | 'completed'
  | 'failed';

export type RecordingType =
  | 'meeting'
  | 'lecture'
  | 'interview'
  | 'voice_note'
  | 'call';

export type TimestampLike =
  | string
  | number
  | {
      _seconds?: number;
      seconds?: number;
      nanoseconds?: number;
      _nanoseconds?: number;
    }
  | null
  | undefined;

export type RecordingAudio = {
  s3Key?: string;
  fileUrl?: string;
  fileName?: string;
  mimeType?: string;
  fileSize?: number;
  durationSeconds?: number;
  uploadedAt?: TimestampLike;
};

export type RecordingTranscript = {
  fullText?: string;
  language?: string;
  wordCount?: number;
  provider?: string;
  deepgramRequestId?: string;
  transcribedAt?: TimestampLike;
};

export type RecordingActionItem = {
  task: string;
  owner: string;
  dueDate: string;
  status: 'pending' | 'completed';
};

export type RecordingAi = {
  summary?: string;
  shortSummary?: string;
  keyPoints?: string[];
  decisions?: string[];
  actionItems?: RecordingActionItem[];
  generatedAt?: TimestampLike;
  model?: string;
};

export type RecordingSearch = {
  keywords?: string[];
  embeddingStatus?: RecordingStatus;
  vectorNamespace?: string;
  vectorCollection?: string;
};

export type RecordingStats = {
  chatCount?: number;
  aiRequestCount?: number;
  viewCount?: number;
};

export type RecordingError = {
  message?: string;
  stage?: string;
  code?: string;
};

export type Recording = {
  id: string;
  userId: string;
  title: string;
  description: string;
  type: RecordingType;
  status: RecordingStatus;
  audio: RecordingAudio;
  transcript: RecordingTranscript;
  ai: RecordingAi;
  search: RecordingSearch;
  stats: RecordingStats;
  error: RecordingError;
  createdAt?: TimestampLike;
  updatedAt?: TimestampLike;
  deletedAt?: TimestampLike;
};

export type CreateRecordingPayload = {
  title: string;
  description: string;
  type: RecordingType;
};

export type UpdateRecordingPayload = Partial<CreateRecordingPayload>;

export type UploadUrlPayload = {
  fileName: string;
  mimeType: string;
  fileSize?: number;
  durationSeconds?: number;
};

export type UploadUrlResponse = {
  uploadUrl: string;
  fileUrl: string;
  s3Key: string;
  expiresInSeconds: number;
};

export type UploadCompletePayload = {
  fileSize: number;
  durationSeconds: number;
};

export type ChatSession = {
  id: string;
  userId: string;
  recordingId: string;
  title: string;
  createdAt?: TimestampLike;
  updatedAt?: TimestampLike;
};

export type ChatSessionDetail = ChatSession & {
  messages: ChatMessage[];
};

export type ChatMessageSource = {
  chunkId: string;
  startTime: number;
  endTime: number;
  textPreview: string;
};

export type ChatMessage = {
  id: string;
  userId: string;
  recordingId: string;
  chatId: string;
  role: 'user' | 'assistant';
  content: string;
  sources: ChatMessageSource[];
  model: string;
  tokenUsage?: {
    inputTokens?: number;
    outputTokens?: number;
    totalTokens?: number;
  };
  createdAt?: TimestampLike;
};

export type ChatMessagePair = {
  userMessage: ChatMessage;
  assistantMessage: ChatMessage;
};

export type KeywordSearchResult = {
  recordingId: string;
  title: string;
  status: RecordingStatus;
  matchedFields: string[];
  textPreview: string;
};

export type SemanticSearchResult = {
  recordingId: string;
  chunkId: string;
  score: number;
  title?: string;
  textPreview: string;
  startTime: number;
  endTime: number;
};

export type SearchMode = 'keyword' | 'semantic' | 'hybrid';

export type RecordingSearchResults = {
  query: string;
  mode: SearchMode;
  keywordResults: KeywordSearchResult[];
  semanticResults: SemanticSearchResult[];
};
