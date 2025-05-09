// GTFSExporter.java
package gama.extension.GTFS;

import com.opencsv.CSVWriter;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.List;

public class GTFSExporter {

    public void exportFilteredData(String outputDir, FilteredGtfsData data) {
        try {
            new File(outputDir).mkdirs();

            exportStops(outputDir + "/stops.txt", data.getStops());
            exportTrips(outputDir + "/trips.txt", data.getTrips());
            exportRoutes(outputDir + "/routes.txt", data.getRoutes());
            exportShapes(outputDir + "/shapes.txt", data.getShapes());

        } catch (Exception e) {
            System.err.println("[ERROR] Exporting filtered GTFS: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void exportStops(String path, List<TransportStop> stops) throws IOException {
        try (CSVWriter writer = new CSVWriter(new FileWriter(path))) {
            writer.writeNext(new String[]{"stop_id", "stop_name", "stop_lat", "stop_lon"});
            for (TransportStop stop : stops) {
                writer.writeNext(new String[]{
                    stop.getStopId(),
                    stop.getStopName(),
                    String.valueOf(stop.getLocation().getY()),
                    String.valueOf(stop.getLocation().getX())
                });
            }
        }
    }

    private void exportTrips(String path, List<TransportTrip> trips) throws IOException {
        try (CSVWriter writer = new CSVWriter(new FileWriter(path))) {
            writer.writeNext(new String[]{"route_id", "service_id", "trip_id", "shape_id"});
            for (TransportTrip trip : trips) {
                writer.writeNext(new String[]{
                    trip.getRouteId(),
                    trip.getServiceId(),
                    String.valueOf(trip.getTripId()),
                    String.valueOf(trip.getShapeId())
                });
            }
        }
    }

    private void exportRoutes(String path, List<TransportRoute> routes) throws IOException {
        try (CSVWriter writer = new CSVWriter(new FileWriter(path))) {
            writer.writeNext(new String[]{"route_id", "route_short_name", "route_long_name", "route_type"});
            for (TransportRoute route : routes) {
                writer.writeNext(new String[]{
                    route.getRouteId(),
                    route.getShortName(),
                    route.getLongName(),
                    String.valueOf(route.getType())
                });
            }
        }
    }

    private void exportShapes(String path, List<TransportShape> shapes) throws IOException {
        try (CSVWriter writer = new CSVWriter(new FileWriter(path))) {
            writer.writeNext(new String[]{"shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence"});
            for (TransportShape shape : shapes) {
                int index = 0;
                for (var point : shape.getPoints()) {
                    writer.writeNext(new String[]{
                        String.valueOf(shape.getShapeId()),
                        String.valueOf(point.getY()),
                        String.valueOf(point.getX()),
                        String.valueOf(index++)
                    });
                }
            }
        }
    }
}
