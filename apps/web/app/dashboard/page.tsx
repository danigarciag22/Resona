import { getDashboardStats } from "@/lib/stats";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";

export const dynamic = "force-dynamic";

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm text-muted-foreground">{label}</CardTitle>
      </CardHeader>
      <CardContent className="text-3xl font-bold">{value}</CardContent>
    </Card>
  );
}

export default async function DashboardPage() {
  const stats = await getDashboardStats();
  return (
    <div>
      <h1 className="mb-6 text-2xl font-bold">Command Center</h1>
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <Stat label="Agents" value={stats.agents} />
        <Stat label="Phone Numbers" value={stats.phoneNumbers} />
        <Stat label="Calls" value={stats.calls} />
        <Stat label="Completed" value={stats.completedCalls} />
      </div>
    </div>
  );
}
