
package utils;

import com.vividsolutions.jts.geom.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.List;

/**
 * Minimal Shapefile writer for Point and LineString geometries (no DBF).
 * Output: very basic .shp only (no .shx, no .dbf, no .prj)
 */
public class ShapefileWriter {

    public static void writeLineStrings(List<LineString> lines, File outFile) throws IOException {
        FileOutputStream fos = new FileOutputStream(outFile);
        DataOutputStream dos = new DataOutputStream(fos);

        // ---- HEADER ----
        ByteBuffer header = ByteBuffer.allocate(100);
        header.order(ByteOrder.BIG_ENDIAN);
        header.putInt(9994); // File code
        for (int i = 0; i < 5; i++) header.putInt(0); // unused
        header.order(ByteOrder.LITTLE_ENDIAN);
        header.putInt(50 + lines.size() * 4); // file length (approx)
        header.putInt(1000); // version
        header.putInt(3); // shape type = PolyLine
        Envelope env = computeEnvelope(lines);
        header.putDouble(env.getMinX());
        header.putDouble(env.getMinY());
        header.putDouble(env.getMaxX());
        header.putDouble(env.getMaxY());
        for (int i = 0; i < 4; i++) header.putDouble(0.0); // Z / M
        dos.write(header.array());

        // ---- RECORDS ----
        int recordNumber = 1;
        for (LineString line : lines) {
            ByteArrayOutputStream recordContent = new ByteArrayOutputStream();
            DataOutputStream record = new DataOutputStream(recordContent);

            record.writeInt(3); // shape type
            record.writeDouble(line.getEnvelopeInternal().getMinX());
            record.writeDouble(line.getEnvelopeInternal().getMinY());
            record.writeDouble(line.getEnvelopeInternal().getMaxX());
            record.writeDouble(line.getEnvelopeInternal().getMaxY());
            record.writeInt(1); // num parts
            record.writeInt(line.getNumPoints());
            record.writeInt(0); // start index of part 0

            for (Coordinate coord : line.getCoordinates()) {
                record.writeDouble(coord.x);
                record.writeDouble(coord.y);
            }

            byte[] recBytes = recordContent.toByteArray();
            dos.writeInt(recordNumber++);
            dos.writeInt(recBytes.length / 2);
            dos.write(recBytes);
        }

        dos.close();
    }

    private static Envelope computeEnvelope(List<LineString> lines) {
        Envelope env = new Envelope();
        for (LineString line : lines) {
            env.expandToInclude(line.getEnvelopeInternal());
        }
        return env;
    }
}
