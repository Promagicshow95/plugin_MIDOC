package gama.extension.GTFS.skills;


import gama.core.runtime.IScope;
import gama.extension.GTFS.GTFS_reader;
import gama.extension.GTFS.export.GTFSShapeExporter;
import gama.gaml.skills.Skill;
import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.action;
import gama.annotations.precompiler.GamlAnnotations.doc;

/**
 * Skill pour exporter les shapes GTFS en shapefile via une action GAMA.
 */
@skill(
    name = "gtfs_export",
    concept = {}
)
public class GTFSExportSkill extends Skill {

    @action(
        name = "export_shapes_to_shapefile",
        doc = @doc("Exporte les shapes GTFS en shapefile routes.shp dans le dossier includes du projet.")
    )
    public Object exportShapesToShapefile(final IScope scope) {
        try {
            // 1. Récupérer GTFS_reader déclaré globalement (ex: gtfs_f)
        	GTFS_reader reader = (GTFS_reader) scope.getGlobalVarValue("gtfs_f");
            if (reader == null) {
                throw new RuntimeException("Variable globale gtfs_f non trouvée !");
            }
            // 2. Définir le dossier de sortie (ex: "includes")
            String outputPath = scope.getModel().getProjectPath() + "/includes";

            // 3. Appeler la méthode d'export GeoTools
            GTFSShapeExporter.exportRouteShapesFromGTFS(scope, reader, outputPath);

            // 4. Message de succès dans la console GAMA
            if (scope.getGui() != null) {
                scope.getGui().getConsole().informConsole("✅ Export GTFS -> Shapefile terminé dans " + outputPath, scope.getSimulation());
            }
        } catch (Exception e) {
            if (scope.getGui() != null) {
                scope.getGui().getConsole().informConsole("❌ Erreur export GTFS vers shapefile : " + e.getMessage(), scope.getSimulation());
            }
            e.printStackTrace();
        }
        return null;
    }
}