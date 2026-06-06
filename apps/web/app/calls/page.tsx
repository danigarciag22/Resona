import Link from "next/link";
import { listCalls, searchCalls } from "@/lib/calls";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export const dynamic = "force-dynamic";

export default async function CallsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const query = (q ?? "").trim();
  const calls = query ? await searchCalls(query) : await listCalls();

  return (
    <div className="max-w-4xl">
      <h1 className="mb-6 text-2xl font-bold">Call Library</h1>

      <form action="/calls" method="get" className="mb-6 flex gap-2">
        <Input
          name="q"
          defaultValue={query}
          placeholder="Search transcripts (e.g. refund)"
        />
        <Button type="submit">Search</Button>
      </form>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Direction</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Duration</TableHead>
            <TableHead>Started</TableHead>
            <TableHead></TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {calls.map((c) => (
            <TableRow key={c.id}>
              <TableCell className="capitalize">{c.direction}</TableCell>
              <TableCell className="capitalize">{c.status}</TableCell>
              <TableCell>
                {c.duration_ms ? `${Math.round(c.duration_ms / 1000)}s` : "—"}
              </TableCell>
              <TableCell>
                {c.started_at ? new Date(c.started_at).toLocaleString() : "—"}
              </TableCell>
              <TableCell>
                <Link className="text-sky-600 hover:underline" href={`/calls/${c.id}`}>
                  Open
                </Link>
              </TableCell>
            </TableRow>
          ))}
          {calls.length === 0 && (
            <TableRow>
              <TableCell colSpan={5} className="text-muted-foreground">
                No calls{query ? ` matching “${query}”` : ""}.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </div>
  );
}
