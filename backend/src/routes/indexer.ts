import { Router, Request, Response } from "express"
import { startIndexer, stopIndexer, getIndexerStatus } from "../indexer/index"

const router = Router()

router.get("/", (_req: Request, res: Response) => {
  res.json(getIndexerStatus())
})

router.post("/", async (req: Request, res: Response) => {
  try {
    const action = (req.body as { action?: string }).action ?? "start"

    if (action === "start") {
      const result = await startIndexer()
      res.json(result)
      return
    }

    if (action === "stop") {
      const result = stopIndexer()
      res.json(result)
      return
    }

    res.status(400).json({ error: `Unknown action: ${action}. Use "start" or "stop".` })
  } catch (error) {
    console.error("[routes/indexer] Error:", error)
    res.status(500).json({
      error: "Indexer operation failed",
      details: error instanceof Error ? error.message : "Unknown",
    })
  }
})

export default router
