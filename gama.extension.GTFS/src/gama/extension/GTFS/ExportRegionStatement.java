// ExportRegionStatement.java
package gama.extension.GTFS;

import gama.core.runtime.IScope;
import gama.core.runtime.exceptions.GamaRuntimeException;
import gama.gaml.descriptions.StatementDescription;
import gama.gaml.expressions.IExpression;


import gama.gaml.statements.AbstractStatement;

import org.locationtech.jts.geom.Geometry;



public class ExportRegionStatement extends AbstractStatement {

    private final IExpression regionExpr;
    private final IExpression outputPathExpr;
    private final IExpression readerExpr;

    public ExportRegionStatement(StatementDescription desc) {
        super(desc);
        this.regionExpr = getFacet("region");
        this.outputPathExpr = getFacet("output_path");
        this.readerExpr = getFacet("reader");
    }

    @Override
    public Object privateExecuteIn(IScope scope) {
        Geometry region = (Geometry) regionExpr.value(scope);
        String outputPath = (String) outputPathExpr.value(scope);
        GTFS_reader reader = (GTFS_reader) readerExpr.value(scope);

        SpatialExtractor extractor = new SpatialExtractor(reader, scope);
        FilteredGtfsData filtered = extractor.filterGTFSByRegion(region);

        GTFSExporter exporter = new GTFSExporter();
        exporter.exportFilteredData(outputPath, filtered);

        scope.getGui().getConsole().informConsole("GTFS export completed to: " + outputPath, scope.getSimulation());
        return null;
    }
}
