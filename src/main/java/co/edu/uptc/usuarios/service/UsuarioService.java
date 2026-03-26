package co.edu.uptc.usuarios.service;
import java.util.List;

import org.springframework.stereotype.Service;

import co.edu.uptc.usuarios.dto.UsuarioDTO;
import co.edu.uptc.usuarios.model.Usuario;
import co.edu.uptc.usuarios.repository.UsuarioRepository;

@Service
public class UsuarioService {

    private final UsuarioRepository usuarioRepository;

    public UsuarioService(UsuarioRepository usuarioRepository) {
        this.usuarioRepository = usuarioRepository;
    }

    public List<Usuario> obtenerTodos() {
        return usuarioRepository.findAll();
    }

    public Usuario obtenerPorId(Integer id) {
        return usuarioRepository.findById(id).orElse(null);
    }

    public UsuarioDTO guardar(UsuarioDTO request) {
        Usuario nuevo = new Usuario();
        nuevo.setName(request.getName());
        nuevo.setUsername(request.getUsername());
        nuevo.setEmail(request.getEmail());
        Usuario guardado = usuarioRepository.save(nuevo);

        UsuarioDTO response = new UsuarioDTO();
        response.setId(guardado.getId());
        response.setName(guardado.getName());
        response.setUsername(guardado.getUsername());
        response.setEmail(guardado.getEmail());
        response.setMessage("Usuario guardado en PostgreSQL correctamente");

        return response;
    }
}
