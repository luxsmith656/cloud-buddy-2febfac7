import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "sonner";
import { AlertTriangle, CheckCircle, ArrowRight, Factory } from "lucide-react";

const batchStatusStyles: Record<string, string> = {
  planned: "bg-info/10 text-info border-info/20",
  "in-progress": "bg-warning/10 text-warning border-warning/20",
  completed: "bg-success/10 text-success border-success/20",
};

const BatchProduction = () => {
  const [wizardOpen, setWizardOpen] = useState(false);
  const [step, setStep] = useState(1);
  const [selectedProduct, setSelectedProduct] = useState("");
  const [quantity, setQuantity] = useState(100);
  const [ingredientCheck, setIngredientCheck] = useState<{ name: string; required: number; available: number; unit: string; sufficient: boolean }[]>([]);
  const queryClient = useQueryClient();

  const { data: products = [] } = useQuery({
    queryKey: ["products"],
    queryFn: async () => {
      const { data, error } = await supabase.from("products").select("*");
      if (error) throw error;
      return data;
    },
  });

  const { data: batches = [], isLoading } = useQuery({
    queryKey: ["batches"],
    queryFn: async () => {
      const { data, error } = await supabase.from("batches").select("*").order("created_at", { ascending: false });
      if (error) throw error;
      return data;
    },
  });

  const { data: recipes = [] } = useQuery({
    queryKey: ["recipes-with-ingredients"],
    queryFn: async () => {
      const { data, error } = await supabase.from("recipes").select("*, recipe_ingredients(*, ingredients(*))");
      if (error) throw error;
      return data;
    },
  });

  const getProduct = (id: string) => products.find(p => p.id === id);

  // Step 2: Pre-flight check
  const runPreFlightCheck = () => {
    const recipe = recipes.find((r: any) => r.product_id === selectedProduct);
    if (!recipe || !(recipe as any).recipe_ingredients?.length) {
      toast.error("No recipe found for this product. Please create a recipe first.");
      return;
    }
    const checks = (recipe as any).recipe_ingredients.map((ri: any) => {
      const ing = ri.ingredients;
      const required = ri.quantity * quantity;
      return {
        name: ing?.name || "Unknown",
        required,
        available: ing?.current_stock || 0,
        unit: ing?.unit || "",
        sufficient: (ing?.current_stock || 0) >= required,
      };
    });
    setIngredientCheck(checks);
    setStep(2);
  };

  const allSufficient = ingredientCheck.every(i => i.sufficient);

  // Step 3: Create batch and deduct ingredients atomically in the database.
  const createBatchMutation = useMutation({
    mutationFn: async () => {
      if (!selectedProduct) throw new Error("Select a product");
      const { error } = await supabase.rpc("produce_batch", {
        product_id_value: selectedProduct,
        quantity_value: quantity,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["batches"] });
      queryClient.invalidateQueries({ queryKey: ["products"] });
      queryClient.invalidateQueries({ queryKey: ["ingredients"] });
      queryClient.invalidateQueries({ queryKey: ["stock_movements"] });
      setWizardOpen(false);
      setStep(1);
      setSelectedProduct("");
      setQuantity(100);
      setIngredientCheck([]);
      toast.success("Batch created successfully! Ingredients deducted and product stock updated.");
    },
    onError: (e) => toast.error(e.message),
  });

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-heading text-3xl font-bold text-foreground">Batch Production</h1>
          <p className="text-muted-foreground mt-1">Create and track production batches with automatic ingredient deduction.</p>
        </div>
        <Button onClick={() => { setStep(1); setWizardOpen(true); }} className="bg-primary hover:bg-primary/90 text-primary-foreground gap-2">
          <Factory className="h-4 w-4" /> Start New Batch
        </Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {isLoading ? (
            <div className="p-8 text-center text-muted-foreground">Loading...</div>
          ) : batches.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground">No batches yet. Start your first production batch!</div>
          ) : (
            <table className="w-full">
              <thead>
                <tr className="border-b border-border">
                  {["Product", "Planned", "Produced", "Production Date", "Expiration", "Status"].map(h => (
                    <th key={h} className="text-left p-4 text-xs font-semibold uppercase tracking-wider text-muted-foreground">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {batches.map(b => {
                  const product = getProduct(b.product_id);
                  return (
                    <tr key={b.id} className="border-b border-border last:border-0 hover:bg-muted/30 transition-colors">
                      <td className="p-4 text-sm text-foreground">{product?.name || "Unknown"} {product?.variant ? `(${product.variant})` : ""}</td>
                      <td className="p-4 text-sm text-foreground">{b.quantity_planned}</td>
                      <td className="p-4 text-sm text-foreground">{b.quantity_produced}</td>
                      <td className="p-4 text-sm text-muted-foreground">{b.production_date}</td>
                      <td className="p-4 text-sm text-muted-foreground">{b.expiration_date || "-"}</td>
                      <td className="p-4">
                        <span className={`text-xs font-medium px-2.5 py-1 rounded-full border ${batchStatusStyles[b.status]}`}>
                          {b.status.toUpperCase()}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      {/* 3-Step Batch Production Wizard */}
      <Dialog open={wizardOpen} onOpenChange={setWizardOpen}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle className="font-heading">
              {step === 1 ? "Step 1: Production Request" : step === 2 ? "Step 2: Pre-Flight Check" : "Step 3: Confirm Production"}
            </DialogTitle>
            <div className="flex gap-2 mt-2">
              {[1, 2, 3].map(s => (
                <div key={s} className={`h-1.5 flex-1 rounded-full ${s <= step ? "bg-primary" : "bg-muted"}`} />
              ))}
            </div>
          </DialogHeader>

          {step === 1 && (
            <div className="space-y-4">
              <div className="space-y-1.5">
                <Label className="text-xs uppercase tracking-wider text-muted-foreground">Select Product</Label>
                <Select value={selectedProduct} onValueChange={setSelectedProduct}>
                  <SelectTrigger><SelectValue placeholder="Choose a product..." /></SelectTrigger>
                  <SelectContent>
                    {products.map(p => <SelectItem key={p.id} value={p.id}>{p.name} {p.variant ? `(${p.variant})` : ""}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs uppercase tracking-wider text-muted-foreground">Quantity to Produce</Label>
                <Input type="number" min="1" value={quantity} onChange={(e) => setQuantity(Math.max(1, Number(e.target.value)))} />
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setWizardOpen(false)}>Cancel</Button>
                <Button onClick={runPreFlightCheck} disabled={!selectedProduct} className="bg-primary text-primary-foreground gap-2">
                  Check Ingredients <ArrowRight className="h-4 w-4" />
                </Button>
              </DialogFooter>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Producing <strong>{quantity}</strong> units of <strong>{getProduct(selectedProduct)?.name}</strong>
              </p>
              <div className="space-y-2 max-h-60 overflow-y-auto">
                {ingredientCheck.map((ic, idx) => (
                  <div key={idx} className={`flex items-center justify-between p-3 rounded-lg border ${ic.sufficient ? "border-success/20 bg-success/5" : "border-destructive/20 bg-destructive/5"}`}>
                    <div className="flex items-center gap-2">
                      {ic.sufficient ? <CheckCircle className="h-4 w-4 text-success" /> : <AlertTriangle className="h-4 w-4 text-destructive" />}
                      <span className="text-sm font-medium text-foreground">{ic.name}</span>
                    </div>
                    <div className="text-right text-sm">
                      <span className={ic.sufficient ? "text-success" : "text-destructive"}>
                        Need: {ic.required.toFixed(2)} {ic.unit}
                      </span>
                      <span className="text-muted-foreground ml-2">/ Have: {ic.available} {ic.unit}</span>
                    </div>
                  </div>
                ))}
              </div>
              {!allSufficient && (
                <p className="text-sm text-destructive font-medium">⚠ Insufficient ingredients. Reduce quantity or restock.</p>
              )}
              <DialogFooter>
                <Button variant="outline" onClick={() => setStep(1)}>Back</Button>
                <Button onClick={() => setStep(3)} disabled={!allSufficient} className="bg-primary text-primary-foreground gap-2">
                  Confirm <ArrowRight className="h-4 w-4" />
                </Button>
              </DialogFooter>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-4">
              <Card className="bg-accent/50 border-accent">
                <CardContent className="p-4 space-y-2">
                  <p className="text-sm"><strong>Product:</strong> {getProduct(selectedProduct)?.name}</p>
                  <p className="text-sm"><strong>Quantity:</strong> {quantity} units</p>
                  <p className="text-sm"><strong>Ingredients to deduct:</strong> {ingredientCheck.length} items</p>
                  <p className="text-xs text-muted-foreground mt-2">This will deduct ingredients from stock and add finished products to inventory.</p>
                </CardContent>
              </Card>
              <DialogFooter>
                <Button variant="outline" onClick={() => setStep(2)}>Back</Button>
                <Button onClick={() => createBatchMutation.mutate()} disabled={createBatchMutation.isPending} className="bg-primary text-primary-foreground gap-2">
                  {createBatchMutation.isPending ? "Processing..." : "Start Production"} <Factory className="h-4 w-4" />
                </Button>
              </DialogFooter>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default BatchProduction;
