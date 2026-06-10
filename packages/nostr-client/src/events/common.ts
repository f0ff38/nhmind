import { NHMIND_CLIENT_TAG } from "../constants";

export function clientTag(): [string, string] {
  return ["client", NHMIND_CLIENT_TAG];
}

export function compactJson(value: unknown): string {
  return JSON.stringify(value);
}

export function getTagValue(
  tags: string[][],
  name: string,
): string | undefined {
  const tag = tags.find(([key]) => key === name);
  return tag?.[1];
}

export function requireTagValue(tags: string[][], name: string): string {
  const value = getTagValue(tags, name);
  if (!value) {
    throw new Error(`missing required tag: ${name}`);
  }
  return value;
}

export function parseJsonContent<T>(content: string): T {
  try {
    return JSON.parse(content) as T;
  } catch {
    throw new Error("invalid JSON content");
  }
}
