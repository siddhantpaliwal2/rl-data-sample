import type { RecordingStatus, TimestampLike } from './types';

const statusLabels: Record<RecordingStatus, string> = {
  completed: 'Completed',
  embedding: 'Embedding',
  failed: 'Failed',
  summarizing: 'Summarizing',
  transcribed: 'Transcribed',
  transcribing: 'Transcribing',
  uploaded: 'Uploaded',
  uploading: 'Uploading',
};

export const formatStatus = (status: RecordingStatus) => {
  return statusLabels[status] ?? status;
};

//----------------------------------------------------------------------------------------------------------------

export const formatDuration = (seconds = 0) => {
  const safeSeconds = Math.max(Math.floor(seconds), 0);
  const minutes = Math.floor(safeSeconds / 60);
  const remainingSeconds = safeSeconds % 60;

  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;

    return `${hours}h ${remainingMinutes}m`;
  }

  return `${minutes}:${String(remainingSeconds).padStart(2, '0')}`;
};

//----------------------------------------------------------------------------------------------------------------

export const formatBytes = (bytes = 0) => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;

  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

//----------------------------------------------------------------------------------------------------------------

export const formatDate = (timestamp: TimestampLike) => {
  if (!timestamp) return 'Not available';

  const date =
    typeof timestamp === 'string' || typeof timestamp === 'number'
      ? new Date(timestamp)
      : new Date((timestamp._seconds ?? timestamp.seconds ?? 0) * 1000);

  if (Number.isNaN(date.getTime())) return 'Not available';

  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(date);
};

//----------------------------------------------------------------------------------------------------------------

export const truncate = (text: string, length = 140) => {
  if (text.length <= length) return text;

  return `${text.slice(0, length).trim()}...`;
};

