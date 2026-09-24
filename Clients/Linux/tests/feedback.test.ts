import { expect, test } from "bun:test";
import { RecordingFeedback } from "../src/feedback.ts";

test("feedback distinguishes silence from absent or stale levels and freezes the actual recording clock", () => {
  const feedback = new RecordingFeedback();
  feedback.begin(174000, 2000);
  expect(feedback.snapshot(2000).levels).toEqual([]);
  feedback.update(0, "Hello", "receiving", 2000);
  expect(feedback.snapshot(2000).levels).toEqual([0]);
  for (let n = 0; n < 12; n++) feedback.update(0.5, "Hello", "receiving", 2200);
  expect(feedback.snapshot(2300).levels).toHaveLength(9);
  expect(feedback.snapshot(4000).levels).toEqual([]);
  expect(feedback.snapshot(144000)).toMatchObject({ elapsedSeconds: 142, remainingSeconds: 30 });
  feedback.finish(true, 174000);
  feedback.update(0.8, "Hello world", "proofreading", 175000);
  expect(feedback.snapshot(190000)).toMatchObject({
    levels: [],
    elapsedSeconds: 172,
    remainingSeconds: null,
    limitReached: true,
    partialText: "Hello world",
    processingStage: "proofreading",
  });
  feedback.unavailable();
  expect(feedback.snapshot(190000)).toMatchObject({
    levels: [],
    partialText: "",
    streamAvailable: false,
  });
});
