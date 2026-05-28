import { useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Camera, Search, StopCircle } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { normalizeBarcodeToken } from "@/lib/barcode";

type ScanStatus = "ready" | "scanning" | "found" | "not-found" | "expired" | "near-expiry" | "defective" | "no-camera-permission";

const statusLabels: Record<ScanStatus, string> = {
  ready: "Ready to scan",
  scanning: "Scanning",
  found: "Found",
  "not-found": "Not found",
  expired: "Expired",
  "near-expiry": "Near expiry",
  defective: "Defective",
  "no-camera-permission": "No camera permission",
};

const getBatchStatus = (batch: any): ScanStatus => {
  if (!batch) return "not-found";
  if (batch.defect_quantity > 0) return "defective";
  if (!batch.expiration_date) return "found";
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const expiry = new Date(`${batch.expiration_date}T00:00:00`);
  const days = Math.ceil((expiry.getTime() - today.getTime()) / 86_400_000);
  if (days < 0) return "expired";
  if (days <= 14) return "near-expiry";
  return "found";
};

const BarcodeScanner = () => {
  const [manualCode, setManualCode] = useState("");
  const [status, setStatus] = useState<ScanStatus>("ready");
  const [batch, setBatch] = useState<any | null>(null);
  const [movements, setMovements] = useState<any[]>([]);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanningRef = useRef(false);

  const lookupMutation = useMutation({
    mutationFn: async (code: string) => {
      const normalized = normalizeBarcodeToken(code);
      if (!normalized) throw new Error("Enter or scan a barcode");

      const { data, error } = await supabase.rpc("find_batch_by_barcode", { barcode_value_value: normalized });
      if (error) throw error;
      const found = data?.[0] || null;
      const { data: movementRows } = await supabase
        .from("stock_movements")
        .select("*")
        .or(`batch_code.eq.${normalized},remarks.ilike.%${normalized}%`)
        .order("created_at", { ascending: false })
        .limit(8);
      return { found, movementRows: movementRows || [] };
    },
    onSuccess: ({ found, movementRows }) => {
      setBatch(found);
      setMovements(movementRows);
      setStatus(found ? getBatchStatus(found) : "not-found");
      if (!found) toast.error("No batch found for that barcode");
    },
    onError: (error) => {
      setStatus("not-found");
      toast.error(error.message);
    },
  });

  const stopCamera = () => {
    scanningRef.current = false;
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setStatus(batch ? getBatchStatus(batch) : "ready");
  };

  const startCamera = async () => {
    const BarcodeDetectorCtor = (window as any).BarcodeDetector;
    if (!BarcodeDetectorCtor) {
      toast.error("Camera barcode detection is not available in this browser. Use manual search or a USB scanner.");
      setStatus("ready");
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      const detector = new BarcodeDetectorCtor({ formats: ["code_128", "qr_code", "ean_13", "code_39"] });
      scanningRef.current = true;
      setStatus("scanning");

      const scan = async () => {
        if (!scanningRef.current || !videoRef.current) return;
        const codes = await detector.detect(videoRef.current).catch(() => []);
        if (codes.length > 0) {
          const rawValue = codes[0].rawValue;
          stopCamera();
          setManualCode(rawValue);
          lookupMutation.mutate(rawValue);
          return;
        }
        requestAnimationFrame(scan);
      };
      requestAnimationFrame(scan);
    } catch {
      setStatus("no-camera-permission");
      toast.error("Camera permission was denied or unavailable");
    }
  };

  useEffect(() => () => {
    scanningRef.current = false;
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }, []);

  return (
    <div className="space-y-6 animate-fade-in">
      <div>
        <h1 className="font-heading text-3xl font-bold text-foreground">Barcode Scanner</h1>
        <p className="text-muted-foreground mt-1">Scan an internal batch token to fetch batch details from Cloud Buddy.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[420px_1fr] gap-6">
        <Card>
          <CardContent className="p-5 space-y-4">
            <div className="aspect-video rounded-md border bg-muted overflow-hidden">
              <video ref={videoRef} className="h-full w-full object-cover" muted playsInline />
            </div>
            <Badge variant="outline">{statusLabels[status]}</Badge>
            <div className="flex gap-2">
              <Button onClick={startCamera} disabled={status === "scanning"} className="gap-2 bg-primary text-primary-foreground"><Camera className="h-4 w-4" /> Scan Camera</Button>
              <Button onClick={stopCamera} variant="outline" disabled={status !== "scanning"} className="gap-2"><StopCircle className="h-4 w-4" /> Stop</Button>
            </div>
            <div className="flex gap-2">
              <Input
                autoFocus
                value={manualCode}
                onChange={(event) => setManualCode(event.target.value)}
                onKeyDown={(event) => { if (event.key === "Enter") lookupMutation.mutate(manualCode); }}
                placeholder="Scan or type batch barcode"
              />
              <Button onClick={() => lookupMutation.mutate(manualCode)} variant="outline" className="gap-2"><Search className="h-4 w-4" /> Search</Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-5">
            {!batch ? (
              <div className="p-8 text-center text-muted-foreground">No batch selected. Scan or search a batch barcode.</div>
            ) : (
              <div className="space-y-5">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="text-xs uppercase tracking-wider text-muted-foreground">Batch / Lot</p>
                    <h2 className="font-heading text-2xl font-bold">{batch.batch_code}</h2>
                  </div>
                  <Badge variant={status === "expired" || status === "defective" ? "destructive" : "outline"}>{statusLabels[status]}</Badge>
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <Info label="Product" value={batch.product_name} />
                  <Info label="Category" value={batch.category} />
                  <Info label="Variant" value={batch.variant || "-"} />
                  <Info label="Price / SRP" value={batch.price ? batch.price.toLocaleString(undefined, { style: "currency", currency: "PHP" }) : "-"} />
                  <Info label="Manufactured" value={batch.manufactured_date} />
                  <Info label="Expiration" value={batch.expiration_date} />
                  <Info label="Shelf Life" value={batch.shelf_life ? `${batch.shelf_life} days` : "-"} />
                  <Info label="Status" value={batch.status} />
                  <Info label="Produced" value={String(batch.quantity_produced)} />
                  <Info label="Remaining" value={String(batch.remaining_quantity)} />
                  <Info label="Defects" value={String(batch.defect_quantity)} />
                  <Info label="Token" value={batch.barcode_token} />
                </div>
                <div>
                  <p className="text-xs uppercase tracking-wider text-muted-foreground mb-2">Recent Stock Movements</p>
                  {movements.length === 0 ? <p className="text-sm text-muted-foreground">No movements found for this batch token.</p> : (
                    <div className="space-y-2">
                      {movements.map((movement) => (
                        <div key={movement.id} className="flex justify-between gap-3 rounded-md border p-3 text-sm">
                          <span>{movement.type} {movement.quantity} - {movement.remarks || "-"}</span>
                          <span className="text-muted-foreground">{new Date(movement.created_at).toLocaleDateString()}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
};

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="text-sm font-medium text-foreground break-words">{value}</p>
    </div>
  );
}

export default BarcodeScanner;
