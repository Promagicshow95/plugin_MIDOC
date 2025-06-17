package gama.extension.GTFS.skills;

import gama.annotations.precompiler.GamlAnnotations.action;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.core.runtime.IScope;
import gama.gaml.skills.Skill;
import gama.extension.GTFSfilter.GTFSFilter;
import java.io.File;

@skill(name = "gtfs_filter")
public class GTFSFilterSkill extends Skill {

    @action(name = "filter_gtfs_with_osm", doc = @doc("Filter GTFS files using the bounding box of an OSM file. Global variables gtfs_path, osm_path and output_path must be defined."))
    public Object filterGtfsWithOsm(final IScope scope) {
        try {
            // Récupération des chemins relatifs définis en GAML
            String gtfsRelPath = scope.getGlobalVarValue("gtfs_path").toString();
            String osmRelPath = scope.getGlobalVarValue("osm_path").toString();
            String outputRelPath = scope.getGlobalVarValue("output_path").toString();

            // Résolution manuelle des chemins absolus
            String baseFolder = scope.getModel().getDescription().getModelFolderPath();
            File gtfsAbsPath = new File(baseFolder, gtfsRelPath);
            File osmAbsPath = new File(baseFolder, osmRelPath);
            File outputAbsPath = new File(baseFolder, outputRelPath);

            // Debugging simple (optionnel)
            System.out.println("GTFS absolu: " + gtfsAbsPath.getAbsolutePath());
            System.out.println("OSM absolu: " + osmAbsPath.getAbsolutePath());
            System.out.println("Output absolu: " + outputAbsPath.getAbsolutePath());

            // Appel au filtre GTFS
            GTFSFilter.filter(
                gtfsAbsPath.getAbsolutePath(), 
                osmAbsPath.getAbsolutePath(), 
                outputAbsPath.getAbsolutePath()
            );

            // Message succès console GAMA
            if (scope.getGui() != null) {
                scope.getGui().getConsole().informConsole("✅ GTFS filtered successfully to: " + outputAbsPath.getAbsolutePath(), scope.getSimulation());
            }
        } catch (Exception e) {
            if (scope.getGui() != null) {
                scope.getGui().getConsole().informConsole("❌ Error while filtering GTFS: " + e.getMessage(), scope.getSimulation());
            }
            e.printStackTrace();
        }
        return null;
    }
}
