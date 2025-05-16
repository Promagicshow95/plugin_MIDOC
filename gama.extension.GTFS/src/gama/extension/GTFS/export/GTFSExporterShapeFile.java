package gama.extension.GTFS.export;

import java.io.File;
import java.util.List;
import java.util.ArrayList;

import org.locationtech.jts.geom.*;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.util.IList;
import gama.extension.GTFS.TransportShape;
import utils.ShapefileWriter;

public class GTFSExporterShapeFile {

    public static void exportShapesToShapefile(List<TransportShape> shapeList, String outputPath) throws Exception {
        GeometryFactory factory = new GeometryFactory();
        List<LineString> lines = new ArrayList<>();

        for (TransportShape shape : shapeList) {
        	IList<GamaPoint> pts = shape.getPoints(); 
            Coordinate[] coords = new Coordinate[pts.size()];
            for (int i = 0; i < pts.size(); i++) {
                coords[i] = new Coordinate(pts.get(i).getX(), pts.get(i).getY());
            }
            LineString ls = factory.createLineString(coords);
            lines.add(ls);
        }

        File shapefile = new File(outputPath + "/routes.shp");
        ShapefileWriter.writeLineStrings(lines, shapefile);
        System.out.println("✅ Shapefile créé : " + shapefile.getAbsolutePath());
    }
}
