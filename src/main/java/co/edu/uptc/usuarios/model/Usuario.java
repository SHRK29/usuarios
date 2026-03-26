package co.edu.uptc.usuarios.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "usuarios", schema = "usuarios_schema")
public class Usuario {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false, unique = true)
    private String username;

    @Column(nullable = false, unique = true)
    private String email;

    public Usuario() {
    }

    public Usuario(Integer id, String name, String username, String email) {
        this.id = id;
        this.name = name;
        this.username = username;
        this.email = email;
    }

    public Integer getId() { 
        return id; 
    }
    public void setId(Integer id) {
        this.id = id;
    }
    public String getName() {
        return name; 
    }
    public void setName(String name) {
        this.name = name; 
    }
    public String getUsername() { 
        return username; 
    }
    public void setUsername(String username) {
        this.username = username; 
    }
    public String getEmail() {
        return email; 
    }
    public void setEmail(String email) { 
        this.email = email; 
    }
}
