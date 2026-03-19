package co.edu.uptc.usuarios.controller;

import java.net.InetAddress;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import co.edu.uptc.usuarios.dto.UsuarioDTO;
import co.edu.uptc.usuarios.model.Usuario;
import co.edu.uptc.usuarios.service.UsuarioService;
import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api/usuarios")
public class UsuarioController {

    private final UsuarioService usuarioService;

    @Value("${instance.tag:Soy el programa 1}")
    private String instanceTag;

    public UsuarioController(UsuarioService usuarioService) {
        this.usuarioService = usuarioService;
    }
    @GetMapping
    public List<UsuarioDTO> obtenerTodos() throws Exception {
        String ipServidor = InetAddress.getLocalHost().getHostAddress();
        return usuarioService.obtenerTodos().stream()
                .map(u -> toDto(u, ipServidor))
                .collect(Collectors.toList());
    }
    @GetMapping("/{id}")
    public UsuarioDTO obtenerPorId(@PathVariable Integer id) throws Exception {
    Usuario usuario = usuarioService.obtenerPorId(id);
    String ipServidor = InetAddress.getLocalHost().getHostAddress();
    return toDto(usuario, ipServidor);
}
   @PostMapping
    public UsuarioDTO crearUsuario(@RequestBody UsuarioDTO dto,HttpServletRequest request) throws Exception {
    UsuarioDTO response = usuarioService.guardar(dto);
    String ipServidor = InetAddress.getLocalHost().getHostAddress();
    response.setIpAddress(ipServidor);
    response.setInstanceTag(instanceTag);
    return response;
}

    private UsuarioDTO toDto(Usuario usuario, String ipServidor) {
        if (usuario == null) {
            return null;
        }
        UsuarioDTO dto = new UsuarioDTO();
        dto.setId(usuario.getId());
        dto.setName(usuario.getName());
        dto.setUsername(usuario.getUsername());
        dto.setEmail(usuario.getEmail());
        dto.setIpAddress(ipServidor);
        dto.setInstanceTag(instanceTag);
        return dto;
    }
}
