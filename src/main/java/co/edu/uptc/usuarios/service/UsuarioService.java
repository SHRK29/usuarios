package co.edu.uptc.usuarios.service;
import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import jakarta.annotation.PostConstruct;

import co.edu.uptc.usuarios.dto.UsuarioDTO;
import co.edu.uptc.usuarios.model.Usuario;

@Service
public class UsuarioService {

    @Value("${data.dir:./data}")
    private String dataDir;

    @Value("${data.file:usuarios.txt}")
    private String dataFile;

    private Path dataPath;
    @PostConstruct
    private void init() {
        dataPath = Path.of(dataDir, dataFile);
        inicializarArchivo();
    }

    private void inicializarArchivo() {
        try {
            Path parent = dataPath.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
            if (!Files.exists(dataPath)) {
                Files.createFile(dataPath);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public List<Usuario> obtenerTodos() {

        List<Usuario> usuarios = new ArrayList<>();

        try {
            List<String> lineas = Files.readAllLines(dataPath);

            for (String lineaBase64 : lineas) {

                byte[] decodedBytes = Base64.getDecoder().decode(lineaBase64);
                String linea = new String(decodedBytes);

                String[] datos = linea.split(",");

                Usuario usuario = new Usuario(
                        Integer.parseInt(datos[0]),
                        datos[1],
                        datos[2],
                        datos[3]
                );

                usuarios.add(usuario);

            }

        } catch (IOException e) {
            e.printStackTrace();
        }

        return usuarios;
    }

    public Usuario obtenerPorId(Integer id) {
        return obtenerTodos().stream()
                .filter(u -> u.getId().equals(id))
                .findFirst()
                .orElse(null);
    }

    public UsuarioDTO guardar(UsuarioDTO request) {

        Integer nextId = calcularSiguienteId();
        Usuario nuevo = new Usuario(
                nextId,
                request.getName(),
                request.getUsername(),
                request.getEmail()
        );

        String linea = nuevo.getId() + "," +
                nuevo.getName() + "," +
                nuevo.getUsername() + "," +
                nuevo.getEmail();

        String encoded = Base64.getEncoder().encodeToString(linea.getBytes());

        try (BufferedWriter writer = new BufferedWriter(new FileWriter(dataPath.toFile(), true))) {
            writer.write(encoded);
            writer.newLine();
        } catch (IOException e) {
            e.printStackTrace();
        }

        UsuarioDTO response = new UsuarioDTO();
        response.setId(nuevo.getId());
        response.setName(nuevo.getName());
        response.setUsername(nuevo.getUsername());
        response.setEmail(nuevo.getEmail());
        response.setMessage("Usuario guardado en archivo correctamente");

        return response;
    }

    private Integer calcularSiguienteId() {
        List<Usuario> usuarios = obtenerTodos();
        int maxId = 0;
        for (Usuario usuario : usuarios) {
            if (usuario.getId() != null && usuario.getId() > maxId) {
                maxId = usuario.getId();
            }
        }
        return maxId + 1;
    }
}
