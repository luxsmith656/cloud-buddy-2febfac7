import { useEffect, useState } from "react";
import { CloudOff, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { applyPendingUpdate, subscribePwa, type PwaStatus } from "@/lib/pwa";

export function PwaStatusBar() {
  const [online, setOnline] = useState(typeof navigator === "undefined" ? true : navigator.onLine);
  const [status, setStatus] = useState<PwaStatus>("idle");

  useEffect(() => {
    const goOnline = () => setOnline(true);
    const goOffline = () => setOnline(false);
    window.addEventListener("online", goOnline);
    window.addEventListener("offline", goOffline);
    const unsub = subscribePwa(setStatus);
    return () => {
      window.removeEventListener("online", goOnline);
      window.removeEventListener("offline", goOffline);
      unsub();
    };
  }, []);

  if (online && status !== "updated") return null;

  return (
    <div className="flex flex-wrap items-center gap-3 border-b border-border bg-muted/60 px-4 py-2 text-xs">
      {!online && (
        <div className="flex items-center gap-2">
          <CloudOff className="h-4 w-4 text-warning" />
          <span className="font-medium text-foreground">Offline mode</span>
          <span className="text-muted-foreground">Showing last-synced data. Server-only actions are paused.</span>
        </div>
      )}
      {status === "updated" && (
        <div className="flex items-center gap-2 ml-auto">
          <RefreshCw className="h-4 w-4 text-primary" />
          <span className="text-foreground">A new version of Cloud Buddy is available.</span>
          <Button size="sm" variant="outline" onClick={() => applyPendingUpdate()}>Reload</Button>
        </div>
      )}
    </div>
  );
}