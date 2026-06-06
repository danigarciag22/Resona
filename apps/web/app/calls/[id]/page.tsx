import { notFound } from "next/navigation";
import { getCallDetail } from "@/lib/calls";
import { Waveform } from "@/components/waveform";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export const dynamic = "force-dynamic";

type Segment = { speaker: string; start_ms: number; end_ms: number; text: string };

export default async function CallPlayerPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const { call, transcript, analysis } = await getCallDetail(id);
  if (!call) notFound();

  const segments = (transcript?.segments as Segment[] | null) ?? [];
  const topics = (analysis?.topics as string[] | null) ?? [];
  const actionItems = (analysis?.action_items as string[] | null) ?? [];

  return (
    <div className="grid max-w-5xl gap-6 md:grid-cols-[2fr_1fr]">
      <div className="space-y-6">
        <h1 className="text-2xl font-bold">Call {call.id.slice(0, 8)}</h1>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm text-muted-foreground">Recording</CardTitle>
          </CardHeader>
          <CardContent>
            {call.recording_uri ? (
              <Waveform url={call.recording_uri} />
            ) : (
              <p className="text-sm text-muted-foreground">
                No recording (live voice pipeline pending — Plan 2b).
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm text-muted-foreground">Transcript</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {segments.map((s, i) => (
              <p key={i} className="text-sm">
                <span className="font-semibold capitalize">{s.speaker}: </span>
                {s.text}
              </p>
            ))}
            {segments.length === 0 && (
              <p className="text-sm text-muted-foreground">No transcript.</p>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm text-muted-foreground">Insights</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <div>
              <div className="font-semibold">Sentiment</div>
              <div>{analysis?.sentiment ?? "—"}</div>
            </div>
            <div>
              <div className="font-semibold">Topics</div>
              <div>{topics.join(", ") || "—"}</div>
            </div>
            <div>
              <div className="font-semibold">Summary</div>
              <div>{analysis?.summary ?? "—"}</div>
            </div>
            <div>
              <div className="font-semibold">Action items</div>
              <ul className="list-disc pl-5">
                {actionItems.map((a, i) => (
                  <li key={i}>{a}</li>
                ))}
                {actionItems.length === 0 && <li className="list-none">—</li>}
              </ul>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
