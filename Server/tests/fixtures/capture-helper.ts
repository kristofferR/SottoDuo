#!/usr/bin/env bun
const [, , command, serial, , , retained] = process.argv;
if (command !== "capture") process.exit(1);
const packet = (type: number, bytes = Buffer.alloc(0)) => {
  const header = Buffer.alloc(8);
  header.writeUInt32LE(type);
  header.writeUInt32LE(bytes.length, 4);
  process.stdout.write(Buffer.concat([header, bytes]));
};
process.stdin.resume();
if (serial !== "2") packet(3);
if (serial === "3") process.exit(1);
if (serial === "4") {
  process.stdin.once("data", () => {
    process.stdout.write(Buffer.from([1, 0, 0]));
    process.exit(0);
  });
} else {
  if (serial === "5") for (let i = 0; i < 1000; i++) packet(2, Buffer.alloc(6400));
  process.stdin.once("data", () => {
    if (retained === "1") for (let i = 0; i < 10; i++) packet(1, Buffer.alloc(4800 * 2 * 4));
    packet(2, Buffer.alloc(16000 * 4));
    packet(4);
    process.stdout.end(() => process.exit(0));
  });
}
