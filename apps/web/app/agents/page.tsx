import { listAgents } from "@/lib/agents";
import { createAgentAction } from "./actions";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";

export const dynamic = "force-dynamic";

export default async function AgentsPage() {
  const agents = await listAgents();
  return (
    <div className="max-w-3xl">
      <h1 className="mb-6 text-2xl font-bold">Agents</h1>

      <form action={createAgentAction} className="mb-8 flex items-end gap-3">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="name">Name</Label>
          <Input id="name" name="name" placeholder="Clinic Scheduler" required />
        </div>
        <div className="flex flex-1 flex-col gap-1.5">
          <Label htmlFor="persona">Persona</Label>
          <Input id="persona" name="persona" placeholder="Friendly, concise" />
        </div>
        <Button type="submit">Create</Button>
      </form>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Name</TableHead>
            <TableHead>Model</TableHead>
            <TableHead>Created</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {agents.map((a) => (
            <TableRow key={a.id}>
              <TableCell className="font-medium">{a.name}</TableCell>
              <TableCell>{a.llm_model}</TableCell>
              <TableCell>{new Date(a.created_at).toLocaleDateString()}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
