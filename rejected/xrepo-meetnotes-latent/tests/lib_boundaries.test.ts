// Boundary / edge-case correctness for the pure library utilities.
//
// These assert behaviour on inputs the app's own tests never feed: a duration
// that lands exactly on the hour boundary, a megabyte-scale byte size, a
// keyword whose letters differ in case from the stored text, a match set larger
// than the requested limit, and a match sitting at the very start of a
// transcript. The mid-range assertions in the same file stay green in both the
// current (buggy) and corrected states, so a regression on these edges is
// invisible to comfortable-value tests while being wrong here.

import { describe, expect, it } from "bun:test";

import { formatBytes, formatDuration } from "../frontend/src/lib/format";
import { searchRecordings } from "../backend/src/services/search.services";
import {
  __setRecordings,
  type AppRecording,
} from "../backend/src/services/recording.services";

const rec = (
  id: string,
  title: string,
  fullText: string,
  status = "completed",
): AppRecording => ({ id, title, status, transcript: { fullText } });

const keywordSearch = (q: string, limit: number) =>
  searchRecordings({ q, mode: "keyword", limit, userId: "user-1" });

//----------------------------------------------------------------------------------------------------------------
// formatDuration

describe("audio duration formatting", () => {
  // f2p: a recording of exactly one hour (and one hour minus a second's worth
  // of remainder) must roll up into the hours-and-minutes form.
  it("rolls a full hour of seconds into hours-and-minutes form", () => {
    expect(formatDuration(3600)).toBe("1h 0m");
    expect(formatDuration(3659)).toBe("1h 0m");
  });

  it("formats sub-hour durations as minutes and seconds", () => {
    expect(formatDuration(0)).toBe("0:00");
    expect(formatDuration(45)).toBe("0:45");
    expect(formatDuration(90)).toBe("1:30");
  });

  it("keeps minutes-and-seconds form just below the hour", () => {
    expect(formatDuration(3599)).toBe("59:59");
  });

  it("keeps hours-and-minutes form above the hour boundary", () => {
    expect(formatDuration(3660)).toBe("1h 1m");
    expect(formatDuration(7325)).toBe("2h 2m");
  });
});

//----------------------------------------------------------------------------------------------------------------
// formatBytes

describe("size formatting", () => {
  // f2p: megabyte-scale sizes must keep a single decimal place.
  it("keeps one decimal place for megabyte sizes", () => {
    expect(formatBytes(1_572_864)).toBe("1.5 MB");
    expect(formatBytes(5 * 1024 * 1024)).toBe("5.0 MB");
  });

  it("formats byte and kilobyte sizes", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(2048)).toBe("2.0 KB");
  });

  it("uses plain bytes below one kilobyte", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(1023)).toBe("1023 B");
  });

  it("stays in kilobytes just below one megabyte", () => {
    expect(formatBytes(1_048_575)).toBe("1024.0 KB");
  });
});

//----------------------------------------------------------------------------------------------------------------
// keyword search matching (case handling)

describe("keyword search matching", () => {
  // f2p: a lowercase query must match stored text that uses different letter
  // case, in both the title and the transcript.
  it("matches a query against stored text regardless of letter case", async () => {
    __setRecordings([
      rec("r-1", "Quarterly Launch Plan", "Meeting about the LAUNCH schedule"),
    ]);

    const res = await keywordSearch("launch", 10);

    expect(res.keywordResults.length).toBe(1);
    expect(res.keywordResults[0].matchedFields).toEqual(["title", "transcript"]);
  });

  it("matches a lowercase query within a same-case title", async () => {
    __setRecordings([rec("r-report", "weekly report", "agenda items only")]);

    const res = await keywordSearch("report", 10);

    expect(res.keywordResults.length).toBe(1);
    expect(res.keywordResults[0].recordingId).toBe("r-report");
    expect(res.keywordResults[0].matchedFields).toEqual(["title"]);
  });

  it("returns nothing when the query is absent", async () => {
    __setRecordings([rec("r-x", "weekly report", "agenda items only")]);

    const res = await keywordSearch("absent-term", 10);

    expect(res.keywordResults.length).toBe(0);
  });
});

//----------------------------------------------------------------------------------------------------------------
// keyword search result count (limit)

describe("keyword search result count", () => {
  // f2p: with more matches than the limit, the result set is capped at the limit.
  it("returns no more results than the requested limit", async () => {
    __setRecordings([
      rec("r-a", "report one", "no keyword here"),
      rec("r-b", "report two", "no keyword here"),
      rec("r-c", "report three", "no keyword here"),
    ]);

    const res = await keywordSearch("report", 2);

    expect(res.keywordResults.length).toBe(2);
  });

  it("returns every match when the match count is under the limit", async () => {
    __setRecordings([
      rec("r-a", "note one", "body"),
      rec("r-b", "note two", "body"),
    ]);

    const res = await keywordSearch("note", 10);

    expect(res.keywordResults.length).toBe(2);
  });
});

//----------------------------------------------------------------------------------------------------------------
// keyword search preview window

describe("keyword search preview", () => {
  // f2p: when the match sits at the very start of a long transcript, the
  // preview is the leading window around the match, not the no-match fallback.
  it("windows the preview around a match at the start of the transcript", async () => {
    const transcript = "launch " + "abcdefghij".repeat(20);
    __setRecordings([rec("r-1", "recording alpha", transcript)]);

    const res = await keywordSearch("launch", 10);

    expect(res.keywordResults[0].textPreview).toBe(transcript.slice(0, 120));
  });

  it("returns the surrounding text for a mid-transcript match", async () => {
    const transcript = "the launch review went well overall";
    __setRecordings([rec("r-1", "review notes", transcript)]);

    const res = await keywordSearch("launch", 10);

    expect(res.keywordResults[0].textPreview).toBe(transcript);
  });

  it("previews the title when the transcript has no text", async () => {
    __setRecordings([rec("r-1", "launch sync", "")]);

    const res = await keywordSearch("launch", 10);

    expect(res.keywordResults[0].matchedFields).toEqual(["title"]);
    expect(res.keywordResults[0].textPreview).toBe("launch sync");
  });
});

//----------------------------------------------------------------------------------------------------------------
// search modes

describe("search modes", () => {
  it("returns empty result sets for semantic mode with no vector hits", async () => {
    __setRecordings([rec("r-1", "launch sync", "the launch is on track")]);

    const res = await searchRecordings({
      q: "launch",
      mode: "semantic",
      limit: 10,
      userId: "user-1",
    });

    expect(res.keywordResults).toEqual([]);
    expect(res.semanticResults).toEqual([]);
  });
});
