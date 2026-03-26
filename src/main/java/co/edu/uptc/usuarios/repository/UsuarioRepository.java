package co.edu.uptc.usuarios.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import co.edu.uptc.usuarios.model.Usuario;

public interface UsuarioRepository extends JpaRepository<Usuario, Integer> {
}
