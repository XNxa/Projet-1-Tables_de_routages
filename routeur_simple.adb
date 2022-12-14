with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings; use Ada.Strings;
with Ada.Text_IO.Unbounded_IO;  use Ada.Text_IO.Unbounded_IO;
with Ada.Integer_Text_IO; use Ada.Integer_Text_IO;
with Ada.Exceptions; use Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Adresse_IP; use Adresse_IP;
with Routage; use Routage;

procedure Routeur_simple is
    
    Option_Erreur : exception; -- Exception levée quand l'utilisateur utilise mal les options

    -- Procedure qui rappelle l'utilisation des options
    -- Cette procédure est appelée lorsque l'exception Option_Erreur est lévée
    procedure Afficher_Utilisation is
    begin
        New_Line;
        Put_Line("Utilisation des options en ligne de commande :");
        Put_Line("-c <taille> : Définir la taille du cache. La valeur 0 indique qu’il n y a pas de cache. La valeur par défaut est 10.");
        Put_Line("-P FIFO|LRU|LFU : Définir la politique utilisée pour le cache (par défaut FIFO)");
        Put_Line("-s : Afficher les statistiques. C’est l’option activée par défaut.");
        Put_Line("-S : Ne pas afficher les statistiques.");
        Put_Line("-t <fichier> : Définir le nom du fichier contenant les routes de la table de routage. Défault : table.txt");
        Put_Line("-p <fichier> : Définir le nom du fichier contenant les paquets à router. Défault : paquet.txt");
        Put_Line("-r <fichier> : Définir le nom du fichier contenant les résultats. Défault : resultats.txt");
    end Afficher_Utilisation;

    -- Surcharge l'opérateur unaire "+" pour convertir une String
	-- en Unbounded_String.
	function "+" (Item : in String) return Unbounded_String
		renames To_Unbounded_String;

    procedure Afficher_Erreur (Message : in String) is 
    begin
        Put_Line(Message);
        raise Option_Erreur;
    end Afficher_Erreur;

    procedure Initialiser_Options (taille_cache : out Integer; politique : out Unbounded_String ; afficher_stat : out Boolean ; 
        f_table : out Unbounded_String ; f_paquet : out Unbounded_String ; f_resultat : out Unbounded_String ) is

        i : Integer := 1;
    begin
        while i <= Argument_Count loop
            
            if Argument(i) = "-c" or Argument(i) = "-P" or Argument(i) = "-t" or Argument(i) = "-p" or Argument(i) = "-r" then
                
                if i+1 <= Argument_Count then

                    if Argument(i) = "-c" then
                        begin
                            taille_cache := Integer'Value(Argument(i+1));
                            exception
                                -- Erreur levée si l'argument après -c n'est pas un entier
                                when CONSTRAINT_ERROR =>
                                    Afficher_Erreur("L'option -c prend un entier en Argument");
                        end;

                    elsif Argument(i) = "-P" then
                        politique := +Argument(i+1);
                        if not (politique = +"FIFO" or politique = +"LFU" or politique = +"LRU") then
                            Afficher_Erreur("Politique choisie inconnue");
                        end if;

                    elsif Argument(i) = "-t" then
                        f_table := +Argument(i+1);
                        if Tail(f_table, 4) /= ".txt" then
                            Afficher_Erreur("Nom de fichier de table incorrect");
                        end if;
                    
                    elsif Argument(i) = "-p" then
                        f_paquet := +Argument(i+1);
                        if Tail(f_paquet, 4) /= ".txt" then
                            Afficher_Erreur("Nom de fichier de paquet incorrect");
                        end if;
                    
                    elsif Argument(i) = "-r" then
                        f_resultat := +Argument(i+1); 
                        if Tail(f_resultat, 4) /= ".txt" then
                            Afficher_Erreur("Nom de fichier de resultat incorrect");
                        end if;
                    end if;

                    i := i + 2;

                else
                    Afficher_Erreur("Mauvais nombre d'argument");
                end if;
            
            elsif Argument(i) = "-s" or Argument(i) = "-S" then
                afficher_stat := (Argument(i) = "-s");
                i := i + 1;
            else
                Afficher_Erreur("Option non reconnue");
            end if;
        end loop;
    end Initialiser_Options;

    procedure Importer_Table (Table_Routage : in out T_Table_Routage ; f_table : in Unbounded_String) is
        FD_Table : File_Type;
        InterfaceLue : Unbounded_String;
        Destination, Masque : T_adresse_ip; 
    begin
        Open(FD_Table, In_File, To_String(f_table));
        -- Ouvrir f_table en lecture
        Initialiser (Table_Routage);
        -- Parcourir les lignes du fichier
        begin
        while not End_Of_File(FD_Table) loop
        -- Séparer la ligne courante en Destination | Masque | Interface

            Lire_Adresse (Destination, FD_Table); -- Destination
            Lire_Adresse (Masque, FD_Table); -- Masque
            InterfaceLue := Get_line(FD_Table); -- Interface
            Trim(InterfaceLue, Both); -- Supprimer les espaces blancs

            -- Enregistrer la ligne courante dans la table de routage
            Enregistrer(Table_Routage, Destination, Masque, InterfaceLue);

        end loop;
        exception
            when End_Error =>
                Put("Attention, Blancs en surplus à la fin du fichier : " & f_table);
        end;
        Close(FD_Table);
    end Importer_Table;

    -- Valeur par défault des options
    taille_cache : Integer := 10;
    politique : Unbounded_String := +"FIFO";
    afficher_stat : Boolean := True;
    f_table : Unbounded_String :=  +"table.txt";
    f_paquet : Unbounded_String := +"paquet.txt";
    f_resultat : Unbounded_String := +"resultats.txt";

    -- Variables pour l'ouverture du fichier f_table
    Table_Routage : T_Table_Routage;

    -- Variables pour l'ecriture des resultats
    FD_Paquet : File_Type;
    Paquet : T_adresse_ip;
    FD_Resultat : File_Type;

begin
    -- Initialiser les options à partir des arguments en ligne de commande
    Initialiser_Options (taille_cache, politique, afficher_stat, f_table, f_paquet, f_resultat);
    
    -- Importer la table de routage depuis le fichier
    Importer_Table (Table_Routage, f_table);
    
    -- Associer chaque paquet à une InterfaceLue
    Open(FD_Paquet, In_File, To_String(f_paquet));
    Create(FD_Resultat, Out_File, To_String(f_resultat));
    begin
    while not End_Of_File(FD_Paquet) loop
    
        -- Lecture d'un Paquet
        Lire_Adresse (Paquet, FD_Paquet);

        -- Enregistrer dans le fichier resultat
        Put(FD_Resultat, To_UString_Base10(Paquet));
        Put(FD_Resultat, " ");
        Put(FD_Resultat, Chercher_Route(Table_Routage, Paquet));
        New_Line(FD_Resultat);

        -- TODO :
        -- Traitement spécial si pas adresse mais mot clé de commande utilisateur

    end loop;
    exception
        when End_Error =>
            Put("Attention, Blancs en surplus à la fin du fichier : " & f_paquet);
    end;
    Close(FD_Paquet);
    Close(FD_Resultat);

    -- Vider la table de routage à la fin de son utilisation    
    Vider(Table_Routage);

    exception
        when Option_Erreur =>
            Afficher_Utilisation;
end Routeur_simple;