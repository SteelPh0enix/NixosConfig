/** `LLAMA_DX_DEBUG=1` writes one stderr line per poll, per scrape and per finished request. */
export const debug = process.env.LLAMA_DX_DEBUG === "1" ? (m: string) => process.stderr.write(`llama-dx: ${m}\n`) : () => void 0;
