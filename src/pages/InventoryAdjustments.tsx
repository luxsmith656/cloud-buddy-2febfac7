import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, X, RefreshCw } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { useAuth } from "@/contexts/AuthContext";
import type { Tables } from "@/integrations/supabase/types";

type AdjustmentRequest = Tables<"inventory_adjustment_requests">;

const statusStyles: Record<AdjustmentRequest["status"], string> = {
  pending: "bg-warning/10 text-warning border-warning/20",
  approved: "bg-success/10 text-success border-success/20",
  rejected: "bg-destructive/10 text-destructive border-destructive/20",
};

export default function InventoryAdjustments() {
  const [reviewTarget, setReviewTarget] = useState<AdjustmentRequest | null>(null);
  const [approve, setApprove] = useState(true);
  const [reviewNote, setReviewNote] = useState("");
  const queryClient = useQueryClient();
  const { isAdmin } = useAuth();

  const { data: requests = [], isLoading } = useQuery({
    queryKey: ["inventory_adjustment_requests"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("inventory_adjustment_requests")
        .select("*")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data;
    },
  });

  const refreshAlertsMutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("refresh_inventory_alerts");
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["alerts"] });
      queryClient.invalidateQueries({ queryKey: ["alerts-all"] });
      queryClient.invalidateQueries({ queryKey: ["alerts-unresolved"] });
      toast.success("Inventory alerts refreshed");
    },
    onError: (e) => toast.error(e.message),
  });

  const reviewMutation = useMutation({
    mutationFn: async () => {
      if (!reviewTarget) throw new Error("Select a request");
      const { error } = await supabase.rpc("review_inventory_adjustment", {
        request_id_value: reviewTarget.id,
        approve_value: approve,
        review_note_value: reviewNote || undefined,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["inventory_adjustment_requests"] });
      queryClient.invalidateQueries({ queryKey: ["stock_movements"] });
      queryClient.invalidateQueries({ queryKey: ["products"] });
      queryClient.invalidateQueries({ queryKey: ["ingredients"] });
      setReviewTarget(null);
      setReviewNote("");
      toast.success(approve ? "Adjustment approved" : "Adjustment rejected");
    },
    onError: (e) => toast.error(e.message),
  });

  const openReview = (request: AdjustmentRequest, shouldApprove: boolean) => {
    setReviewTarget(request);
    setApprove(shouldApprove);
    setReviewNote("");
  };

  const pendingCount = requests.filter((request) => request.status === "pending").length;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="font-heading text-3xl font-bold text-foreground">Adjustment Approvals</h1>
          <p className="text-muted-foreground mt-1">Review stock corrections before they affect inventory.</p>
        </div>
        <Button
          variant="outline"
          onClick={() => refreshAlertsMutation.mutate()}
          disabled={!isAdmin || refreshAlertsMutation.isPending}
          className="gap-2"
        >
          <RefreshCw className="h-4 w-4" /> Refresh Alerts
        </Button>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="p-4 rounded-lg border bg-card">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Pending</p>
          <p className="text-2xl font-bold font-heading text-foreground mt-1">{pendingCount}</p>
        </div>
        <div className="p-4 rounded-lg border bg-card">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Approved</p>
          <p className="text-2xl font-bold font-heading text-foreground mt-1">{requests.filter(r => r.status === "approved").length}</p>
        </div>
        <div className="p-4 rounded-lg border bg-card">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Rejected</p>
          <p className="text-2xl font-bold font-heading text-foreground mt-1">{requests.filter(r => r.status === "rejected").length}</p>
        </div>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {isLoading ? (
            <div className="p-8 text-center text-muted-foreground">Loading adjustment requests...</div>
          ) : requests.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground">No adjustment requests yet.</div>
          ) : (
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  {["Status", "Item", "Type", "Quantity", "Reason", "Requested", "Reviewed", "Actions"].map((heading) => (
                    <th key={heading} className="text-left p-4 text-xs font-semibold uppercase tracking-wider text-muted-foreground">{heading}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {requests.map((request) => (
                  <tr key={request.id} className="border-b border-border last:border-0 hover:bg-muted/30 transition-colors">
                    <td className="p-4">
                      <Badge variant="outline" className={statusStyles[request.status]}>{request.status.toUpperCase()}</Badge>
                    </td>
                    <td className="p-4 text-sm font-medium text-foreground">{request.item_name}</td>
                    <td className="p-4 text-sm text-muted-foreground">{request.item_type}</td>
                    <td className={`p-4 text-sm font-semibold ${request.quantity < 0 ? "text-destructive" : "text-success"}`}>
                      {request.quantity > 0 ? `+${request.quantity}` : request.quantity}
                    </td>
                    <td className="p-4 text-sm text-muted-foreground max-w-xs truncate">{request.reason}</td>
                    <td className="p-4 text-sm text-muted-foreground">{new Date(request.created_at).toLocaleString()}</td>
                    <td className="p-4 text-sm text-muted-foreground">{request.reviewed_at ? new Date(request.reviewed_at).toLocaleString() : "-"}</td>
                    <td className="p-4">
                      {request.status === "pending" ? (
                        <div className="flex items-center gap-2">
                          <Button size="sm" variant="outline" disabled={!isAdmin} onClick={() => openReview(request, true)} className="gap-1">
                            <Check className="h-3.5 w-3.5" /> Approve
                          </Button>
                          <Button size="sm" variant="ghost" disabled={!isAdmin} onClick={() => openReview(request, false)} className="gap-1 text-destructive">
                            <X className="h-3.5 w-3.5" /> Reject
                          </Button>
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground">{request.review_note || "-"}</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!reviewTarget} onOpenChange={() => setReviewTarget(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="font-heading">{approve ? "Approve Adjustment?" : "Reject Adjustment?"}</DialogTitle>
          </DialogHeader>
          {reviewTarget && (
            <div className="space-y-3">
              <div className="rounded-lg border bg-muted/30 p-3 text-sm">
                <p><strong>Item:</strong> {reviewTarget.item_name}</p>
                <p><strong>Quantity:</strong> {reviewTarget.quantity > 0 ? `+${reviewTarget.quantity}` : reviewTarget.quantity}</p>
                <p><strong>Reason:</strong> {reviewTarget.reason}</p>
              </div>
              <Textarea value={reviewNote} onChange={(event) => setReviewNote(event.target.value)} placeholder="Optional review note..." rows={3} />
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setReviewTarget(null)}>Cancel</Button>
            <Button
              variant={approve ? "default" : "destructive"}
              onClick={() => reviewMutation.mutate()}
              disabled={reviewMutation.isPending}
            >
              {reviewMutation.isPending ? "Saving..." : approve ? "Approve" : "Reject"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
