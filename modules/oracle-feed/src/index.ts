import { installLocalStd } from "./runtime/local-std";
import { main } from "./app";

installLocalStd();

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
